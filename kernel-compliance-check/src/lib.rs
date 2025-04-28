mod formatter;
mod models;

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use futures::stream::{self, StreamExt};
use hf_hub::api::tokio::{ApiBuilder, ApiError};
use hf_hub::{Repo, RepoType};
use kernel_abi_check::{check_manylinux, check_python_abi, Version};
use object::Object;
use once_cell::sync::Lazy;

pub use formatter::*;
pub use models::*;

pub use models::{AbiCheckResult, Cli, Commands, CompliantError, Format, Variant};

/// Cached variants to avoid repeatedly fetching the same data
pub static COMPLIANT_VARIANTS: Lazy<(Vec<String>, Vec<String>)> = Lazy::new(|| {
    match fetch_variants_sync() {
        Ok(variants) => variants,
        Err(e) => {
            // We still need to handle initialization errors, but without process::exit
            // This still panics but at least gives proper error context
            panic!("Failed to fetch compliant variants: {}", e);
        }
    }
});

async fn fetch_compliant_variants() -> Result<(Vec<String>, Vec<String>)> {
    let url = "https://raw.githubusercontent.com/huggingface/kernel-builder/refs/heads/main/build-variants.json";
    let response = reqwest::get(url)
        .await
        .context("Failed to connect to variants endpoint")?;

    if !response.status().is_success() {
        return Err(CompliantError::VariantsFetchError(format!(
            "HTTP error: {}",
            response.status()
        ))
        .into());
    }

    let variants_config: VariantsConfig = response
        .json()
        .await
        .context("Failed to parse variants JSON")?;

    let mut cuda_variants = Vec::new();
    cuda_variants.extend(variants_config.x86_64_linux.cuda);
    cuda_variants.extend(variants_config.aarch64_linux.cuda);

    #[cfg(feature = "enable_rocm")]
    let rocm_variants = variants_config.x86_64_linux.rocm;

    #[cfg(not(feature = "enable_rocm"))]
    let rocm_variants = Vec::new();

    Ok((cuda_variants, rocm_variants))
}

/// Synchronous wrapper for fetching variants.
fn fetch_variants_sync() -> Result<(Vec<String>, Vec<String>)> {
    let rt = tokio::runtime::Runtime::new().context("Failed to create Tokio runtime")?;
    rt.block_on(fetch_compliant_variants())
}

pub fn get_cache_dir() -> Result<PathBuf> {
    let cache_dir = if let Ok(dir) = std::env::var("HF_KERNELS_CACHE") {
        PathBuf::from(dir)
    } else {
        dirs::home_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join(".cache/huggingface/hub")
    };

    if !cache_dir.exists() {
        fs::create_dir_all(&cache_dir).context("Failed to create cache directory")?;
    }

    Ok(cache_dir)
}

/// Get "org/name" repo ID from filesystem path
pub fn get_repo_id_from_path(path: &Path) -> Result<String> {
    // Extract the organization and model name from the path
    let dir_name = path
        .file_name()
        .ok_or_else(|| CompliantError::Other(format!("Invalid path: {:?}", path)))?
        .to_string_lossy()
        .to_string();

    // Remove the "models--" prefix if present
    let dir_name = dir_name
        .strip_prefix("models--")
        .unwrap_or(&dir_name)
        .replace("--", "/");

    Ok(dir_name)
}

/// Check if repository has build variants
pub fn has_build_variants(repo_path: &Path) -> Result<bool> {
    // Look for the snapshot directory
    let ref_file = repo_path.join("refs/main");
    if !ref_file.exists() {
        return Ok(false);
    }

    let content = fs::read_to_string(&ref_file)
        .with_context(|| format!("Failed to read ref file: {:?}", ref_file))?;

    let hash = content.trim();
    let snapshot_dir = repo_path.join(format!("snapshots/{}", hash));

    if !snapshot_dir.exists() {
        return Ok(false);
    }

    // Check build directory
    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        return Ok(false);
    }

    // Check if build directory has any variant subdirectories
    let entries = fs::read_dir(&build_dir)
        .with_context(|| format!("Failed to read build directory: {:?}", build_dir))?;

    for entry in entries {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();

        if path.is_dir() {
            // At least one build variant exists
            return Ok(true);
        }
    }

    // Build directory exists but is empty
    Ok(false)
}

pub fn get_repo_path(repo_id: &str, base_dir: &Path) -> PathBuf {
    let repo = Repo::with_revision(repo_id.to_string(), RepoType::Model, "main".to_string());
    base_dir.join(repo.folder_name())
}

async fn fetch_repository_async(
    repo_id: &str,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
) -> Result<()> {
    println!("Repository: {} (revision: {})", repo_id, revision);

    // Check if repository exists and has the requested snapshot
    let cache_dir = get_cache_dir()?;
    let repo_path = get_repo_path(repo_id, &cache_dir);
    let ref_path = repo_path.join("refs").join(revision);

    // Only continue with fetch if force_fetch is true or the repository/revision doesn't exist locally
    if !force_fetch && ref_path.exists() {
        // Read local revision hash
        let local_hash = fs::read_to_string(&ref_path)
            .with_context(|| format!("Failed to read ref file: {:?}", ref_path))?
            .trim()
            .to_string();

        // Check if snapshot exists
        let snapshot_dir = repo_path.join("snapshots").join(&local_hash);
        if snapshot_dir.exists() {
            // Check if build directory exists
            let build_dir = snapshot_dir.join("build");
            if build_dir.exists() {
                println!("Repository is up to date, using local files");
                return Ok(());
            }
        }
    }

    // TODO: improve internal fetching logic to match cli speed/timeouts when downloading
    // to avoid using huggingface-cli

    // Attempt to fetch the repository using huggingface-cli
    if prefer_hub_cli {
        let huggingface_cli =
            std::env::var("HUGGINGFACE_CLI").unwrap_or_else(|_| "huggingface-cli".to_string());

        let mut cmd = std::process::Command::new(&huggingface_cli);
        cmd.arg("download")
            .arg(repo_id)
            .arg("--revision")
            .arg(revision);

        if force_fetch {
            cmd.arg("--force");
        }

        println!("Using huggingface-cli to download repository");

        // Create the command with pipes for stdout and stderr
        let mut child = cmd
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .context("Failed to execute huggingface-cli")?;

        // Process stdout in a separate thread for true real-time output
        let stdout_thread = if let Some(stdout) = child.stdout.take() {
            use std::io::{BufRead, BufReader};
            use std::thread;

            Some(thread::spawn(move || {
                let reader = BufReader::new(stdout);
                for line in reader.lines().map_while(Result::ok) {
                    println!("{}", line);
                }
            }))
        } else {
            None
        };

        // Process stderr in a separate thread too
        let stderr_thread = if let Some(stderr) = child.stderr.take() {
            use std::io::{BufRead, BufReader};
            use std::thread;
            let stderr_copy = stderr;

            Some(thread::spawn(move || {
                let reader = BufReader::new(stderr_copy);
                let mut error_output = String::new();
                for line in reader.lines().map_while(Result::ok) {
                    eprintln!("{}", line); // Print to stderr
                    error_output.push_str(&line);
                    error_output.push('\n');
                }
                error_output
            }))
        } else {
            None
        };

        // Wait for the process to complete
        let status = child.wait().context("Failed to wait for huggingface-cli")?;

        // Wait for stdout thread to finish (if it exists)
        if let Some(stdout_handle) = stdout_thread {
            stdout_handle.join().unwrap();
        }

        // Wait for stderr thread and collect error output if needed
        let stderr_output = if let Some(stderr_handle) = stderr_thread {
            stderr_handle.join().unwrap()
        } else {
            String::new()
        };

        if !status.success() {
            return Err(CompliantError::FetchError(format!(
                "Failed to download repository {}: {}",
                repo_id, stderr_output
            ))
            .into());
        }

        println!("Downloaded repository successfully using huggingface-cli");
        return Ok(());
    }

    // If here use the API to download the repository (fallback)
    println!("Using API to download repository");

    // Create API client
    let api = ApiBuilder::from_env()
        .high()
        .build()
        .context("Failed to create HF API client")?;

    let repo = Repo::with_revision(repo_id.to_string(), RepoType::Model, revision.to_string());
    let api_repo = api.repo(repo);
    // Get repository info and file list
    let info = api_repo
        .info()
        .await
        .context(format!("Failed to fetch repo info for {}", repo_id))?;

    let file_names = info
        .siblings
        .iter()
        .map(|f| f.rfilename.clone())
        .collect::<Vec<_>>();

    // Download files
    println!("Starting download of {} files", file_names.len());

    let download_results = stream::iter(file_names)
        .map(|file_name| {
            // Create a new API instance for each download to avoid shared state issues
            let api = ApiBuilder::new().high().build().unwrap();
            let repo_clone =
                Repo::with_revision(repo_id.to_string(), RepoType::Model, revision.to_string());
            let download_repo = api.repo(repo_clone);

            async move {
                // Implement retry logic with exponential backoff
                let mut retry_count = 0;
                let max_retries = 2;
                let mut delay_ms = 1000;

                loop {
                    match download_repo.download(&file_name).await {
                        Ok(_) => {
                            // Add delay after successful download to avoid rate limiting
                            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                            return Ok(file_name.clone());
                        }
                        Err(e) => {
                            // Special case for __init__.py which can be empty
                            if file_name.contains("__init__.py")
                                && matches!(e, ApiError::RequestError(_))
                            {
                                return Ok(file_name.clone());
                            }

                            if retry_count < max_retries {
                                // Log retry attempt
                                println!(
                                    "Retry {}/{} for file {}: {}",
                                    retry_count + 1,
                                    max_retries,
                                    file_name,
                                    e
                                );

                                // Exponential backoff
                                tokio::time::sleep(tokio::time::Duration::from_millis(delay_ms))
                                    .await;
                                delay_ms *= 2; // Double the delay for next retry
                                retry_count += 1;
                            } else {
                                return Err(anyhow::anyhow!(
                                    "Failed to download {} after {} retries: {}",
                                    file_name,
                                    max_retries,
                                    e
                                ));
                            }
                        }
                    }
                }
            }
        })
        .buffer_unordered(10) // Process up to 10 downloads concurrently
        .collect::<Vec<_>>()
        .await;

    // Count successful downloads and collect errors
    let (successful, failed): (Vec<_>, Vec<_>) =
        download_results.into_iter().partition(Result::is_ok);
    let success_count = successful.len();
    let fail_count = failed.len();

    // If there were failures, report them
    if !failed.is_empty() {
        for error in failed {
            if let Err(e) = error {
                eprintln!("{}", e);
            }
        }
        // Only return an error if all downloads failed
        if success_count == 0 {
            return Err(CompliantError::FetchError(format!(
                "All {} downloads failed for repository {}",
                fail_count, repo_id
            ))
            .into());
        }
    }

    // Log success info
    if force_fetch {
        println!(
            "Force fetched {} files successfully ({} failed)",
            success_count, fail_count
        );
    } else {
        println!(
            "Downloaded {} files successfully ({} failed)",
            success_count, fail_count
        );
    }

    Ok(())
}

/// Synchronous wrapper for the async fetch repository function
pub fn fetch_repository(
    repo_id: &str,
    _cache_dir: &Path,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
) -> Result<()> {
    if force_fetch {
        println!("Mode: Force fetch (redownloading all files)");
    } else {
        println!("Mode: Smart sync (checking for updates)");
    }

    let rt = tokio::runtime::Runtime::new().context("Failed to create Tokio runtime")?;
    rt.block_on(fetch_repository_async(
        repo_id,
        revision,
        force_fetch,
        prefer_hub_cli,
    ))
}

/// Process a single repository with improved snapshot checking
#[allow(clippy::too_many_arguments)]
pub fn process_repository(
    repo_id: &str,
    cache_dir: &Path,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
) -> Result<()> {
    // Check if repository exists and has the requested revision
    let (repo_valid, snapshot_dir, hash) =
        check_repository_revision(repo_id, cache_dir, revision, format)?;

    // If repository has valid snapshot and force_fetch is false, process it directly
    if repo_valid && !force_fetch {
        process_repository_snapshot(
            repo_id,
            &snapshot_dir,
            &hash,
            manylinux,
            python_version,
            compact_output,
            show_violations,
            format,
        )?;
        return Ok(());
    }

    // If repository doesn't exist or needs to be fetched
    if !format.is_json() {
        ConsoleFormatter::format_fetch_status(repo_id, true, None);
    }

    // Fetch the repository
    match fetch_repository(repo_id, cache_dir, revision, force_fetch, prefer_hub_cli) {
        Ok(_) => {
            if !format.is_json() {
                ConsoleFormatter::format_fetch_status(repo_id, false, Some("fetch successful"));
            }

            // Recheck repository after fetch
            let (repo_valid_after, snapshot_dir_after, hash_after) =
                check_repository_revision(repo_id, cache_dir, revision, format)?;

            if !repo_valid_after {
                if !format.is_json() {
                    ConsoleFormatter::format_missing_repo(repo_id);
                } else {
                    let error = RepoErrorResponse {
                        repository: repo_id.to_string(),
                        status: "not_found".to_string(),
                        error: format!("repository not found after fetch: {}", repo_id),
                    };
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&error)
                            .context("Failed to serialize error response")?
                    );
                }
                return Err(CompliantError::RepositoryNotFound(format!(
                    "Repository {} not found after fetch",
                    repo_id
                ))
                .into());
            }

            // Continue processing with fetched repository
            process_repository_snapshot(
                repo_id,
                &snapshot_dir_after,
                &hash_after,
                manylinux,
                python_version,
                compact_output,
                show_violations,
                format,
            )?;
        }
        Err(e) => {
            if !format.is_json() {
                ConsoleFormatter::format_fetch_status(
                    repo_id,
                    false,
                    Some(&format!("fetch failed - {}", e)),
                );
                println!("---");
            } else {
                let error = RepoErrorResponse {
                    repository: repo_id.to_string(),
                    status: "fetch_failed".to_string(),
                    error: e.to_string(),
                };
                println!(
                    "{}",
                    serde_json::to_string_pretty(&error)
                        .context("Failed to serialize error response")?
                );
            }
        }
    }

    Ok(())
}

pub fn get_build_variants(repo_path: &Path) -> Result<Vec<Variant>> {
    let build_dir = repo_path.join("build");
    let mut variants = Vec::new();

    if !build_dir.exists() {
        return Ok(variants);
    }

    let entries = fs::read_dir(&build_dir)
        .with_context(|| format!("Failed to read build directory: {:?}", build_dir))?;

    for entry in entries {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();

        if path.is_dir() {
            let name = path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();

            if let Some(variant) = Variant::from_name(&name) {
                variants.push(variant);
            }
        }
    }

    Ok(variants)
}

/// Generate a build status summary string
pub fn get_build_status_summary(
    build_dir: &Path,
    variants: &[String],
    cuda_variants: &[String],
    #[cfg(feature = "enable_rocm")] rocm_variants: &[String],
    #[cfg(not(feature = "enable_rocm"))] _rocm_variants: &[String],
) -> String {
    let built = variants
        .iter()
        .filter(|v| build_dir.join(v).exists())
        .count();

    let cuda_built = variants
        .iter()
        .filter(|v| cuda_variants.contains(v) && build_dir.join(v).exists())
        .count();

    #[cfg(feature = "enable_rocm")]
    {
        let rocm_built = variants
            .iter()
            .filter(|v| rocm_variants.contains(v) && build_dir.join(v).exists())
            .count();
        format!(
            "Total: {} (CUDA: {}, ROCM: {})",
            built, cuda_built, rocm_built
        )
    }

    #[cfg(not(feature = "enable_rocm"))]
    {
        format!("Total: {} (CUDA: {})", built, cuda_built)
    }
}

pub fn find_shared_objects(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut so_files = Vec::new();

    if !dir.exists() || !dir.is_dir() {
        return Ok(so_files);
    }

    let entries =
        fs::read_dir(dir).with_context(|| format!("Failed to read directory: {:?}", dir))?;

    for entry in entries {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();

        if path.is_dir() {
            let mut subdir_so_files = find_shared_objects(&path)
                .with_context(|| format!("Failed to find .so files in subdirectory: {:?}", path))?;
            so_files.append(&mut subdir_so_files);
        } else if let Some(extension) = path.extension() {
            if extension == "so" {
                so_files.push(path);
            }
        }
    }

    Ok(so_files)
}

pub fn check_shared_object(
    so_path: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    show_violations: bool,
) -> Result<(bool, String)> {
    let mut violations_output = String::new();

    // Read binary data
    let binary_data = fs::read(so_path)
        .with_context(|| format!("Failed to read shared object file: {:?}", so_path))?;

    // Parse object file
    let file = object::File::parse(&*binary_data)
        .map_err(|e| anyhow::anyhow!("Cannot parse object file: {}: {}", so_path.display(), e))?;

    // Run manylinux check
    let manylinux_result = check_manylinux(
        manylinux_version,
        file.architecture(),
        file.endianness(),
        file.symbols(),
    )
    .map_err(|e| anyhow::anyhow!("Manylinux check error: {}", e))?;

    // Run Python ABI check
    let python_abi_result = check_python_abi(python_abi_version, file.symbols())
        .map_err(|e| anyhow::anyhow!("Python ABI check error: {}", e))?;

    // Determine if checks passed
    let passed = manylinux_result.is_empty() && python_abi_result.is_empty();

    // Generate violations output if requested
    if !passed && show_violations {
        if !manylinux_result.is_empty() {
            violations_output.push_str("\n  manylinux violations:\n");
            for violation in &manylinux_result {
                violations_output.push_str(&format!("    - {:?}\n", violation));
            }
        }

        if !python_abi_result.is_empty() {
            violations_output.push_str("\n  python abi violations:\n");
            for violation in &python_abi_result {
                violations_output.push_str(&format!("    - {:?}\n", violation));
            }
        }
    }

    Ok((passed, violations_output))
}

pub fn check_abi_for_repository(
    snapshot_dir: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    show_violations: bool,
) -> Result<AbiCheckResult> {
    let build_dir = snapshot_dir.join("build");

    // If build directory doesn't exist, return empty result
    if !build_dir.exists() {
        return Ok(AbiCheckResult {
            overall_compatible: false,
            variants: Vec::new(),
            manylinux_version: manylinux_version.to_string(),
            python_abi_version: python_abi_version.clone(),
        });
    }

    // Get all variant directories
    let entries = fs::read_dir(&build_dir)
        .with_context(|| format!("Failed to read build directory: {:?}", build_dir))?;

    let variant_paths: Vec<PathBuf> = entries
        .filter_map(|entry_result| match entry_result {
            Ok(entry) => {
                let path = entry.path();
                if path.is_dir() {
                    Some(path)
                } else {
                    None
                }
            }
            Err(_) => None,
        })
        .collect();

    // If no variants found, return empty result
    if variant_paths.is_empty() {
        return Ok(AbiCheckResult {
            overall_compatible: false,
            variants: Vec::new(),
            manylinux_version: manylinux_version.to_string(),
            python_abi_version: python_abi_version.clone(),
        });
    }

    let mut variant_results = Vec::new();

    // Check each variant
    for variant_path in variant_paths.iter() {
        let variant_name = variant_path
            .file_name()
            .ok_or_else(|| {
                CompliantError::Other(format!("Invalid variant path: {:?}", variant_path))
            })?
            .to_string_lossy()
            .to_string();

        let so_files = find_shared_objects(variant_path).with_context(|| {
            format!("Failed to find shared objects in variant: {}", variant_name)
        })?;

        let has_shared_objects = !so_files.is_empty();

        // If no shared objects, mark as compatible and continue
        if !has_shared_objects {
            variant_results.push(VariantResult {
                name: variant_name,
                is_compatible: true,
                violations: Vec::new(),
                has_shared_objects: false,
            });
            continue;
        }

        let mut variant_violations = Vec::new();

        // Check each shared object in the variant
        for so_path in &so_files {
            let (passed, violations_text) = check_shared_object(
                so_path,
                manylinux_version,
                python_abi_version,
                show_violations,
            )
            .with_context(|| format!("Failed to check shared object: {:?}", so_path))?;

            if !passed && show_violations {
                variant_violations.push(SharedObjectViolation {
                    message: violations_text,
                });
            }
        }

        let is_compatible = variant_violations.is_empty();
        variant_results.push(VariantResult {
            name: variant_name,
            is_compatible,
            violations: variant_violations,
            has_shared_objects: true,
        });
    }

    // Determine overall compatibility
    let overall_compatible = variant_results.iter().all(|result| result.is_compatible);

    Ok(AbiCheckResult {
        overall_compatible,
        variants: variant_results,
        manylinux_version: manylinux_version.to_string(),
        python_abi_version: python_abi_version.clone(),
    })
}

/// Process a repository snapshot once we have it
#[allow(clippy::too_many_arguments)]
pub fn process_repository_snapshot(
    repo_id: &str,
    snapshot_dir: &Path,
    _hash: &str,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
) -> Result<()> {
    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        // Print a message indicating the build directory is missing
        if !format.is_json() {
            ConsoleFormatter::format_missing_repo(repo_id);
        } else {
            let error = RepoErrorResponse {
                repository: repo_id.to_string(),
                status: "missing_build_dir".to_string(),
                error: "build directory not found".to_string(),
            };
            println!(
                "{}",
                serde_json::to_string_pretty(&error)
                    .context("Failed to serialize error response")?
            );
        }

        return Err(CompliantError::BuildDirNotFound(repo_id.to_string()).into());
    }

    let variants = get_build_variants(snapshot_dir).context("Failed to get build variants")?;
    let variant_strings: Vec<String> = variants.iter().map(|v| v.to_string()).collect();

    let build_status = get_build_status_summary(
        &build_dir,
        &variant_strings,
        &COMPLIANT_VARIANTS.0,
        &COMPLIANT_VARIANTS.1,
    );

    let abi_output =
        check_abi_for_repository(snapshot_dir, manylinux, python_version, show_violations)
            .with_context(|| format!("Failed to check ABI compatibility for {}", repo_id))?;

    let abi_status = if abi_output.overall_compatible {
        "compatible"
    } else {
        "incompatible"
    };

    // Get present CUDA and ROCM variants
    let cuda_variants_present_set: Vec<&String> = COMPLIANT_VARIANTS
        .0
        .iter()
        .filter(|v| variant_strings.contains(v))
        .collect();

    #[cfg(feature = "enable_rocm")]
    let rocm_variants_present_set: Vec<&String> = COMPLIANT_VARIANTS
        .1
        .iter()
        .filter(|v| variant_strings.contains(v))
        .collect();

    #[cfg(not(feature = "enable_rocm"))]
    let rocm_variants_present_set: Vec<&String> = Vec::new();

    // Check if all required variants are present
    let cuda_compatible = cuda_variants_present_set.len() == COMPLIANT_VARIANTS.0.len();

    #[cfg(feature = "enable_rocm")]
    let rocm_compatible = rocm_variants_present_set.len() == COMPLIANT_VARIANTS.1.len();

    #[cfg(not(feature = "enable_rocm"))]
    let rocm_compatible = true; // When ROCm is disabled, consider it compatible but unused

    if format.is_json() {
        // Create structured data for JSON output
        let cuda_status = CudaStatus {
            compatible: cuda_compatible,
            present: cuda_variants_present_set
                .iter()
                .map(|&v| v.clone())
                .collect(),
            missing: COMPLIANT_VARIANTS
                .0
                .iter()
                .filter(|v| !cuda_variants_present_set.contains(v))
                .cloned()
                .collect(),
        };

        #[cfg(feature = "enable_rocm")]
        let rocm_status = Some(RocmStatus {
            compatible: rocm_compatible,
            present: rocm_variants_present_set
                .iter()
                .map(|&v| v.clone())
                .collect(),
            missing: COMPLIANT_VARIANTS
                .1
                .iter()
                .filter(|v| !rocm_variants_present_set.contains(v))
                .cloned()
                .collect(),
        });

        #[cfg(not(feature = "enable_rocm"))]
        let rocm_status: Option<RocmStatus> = None;

        let variant_outputs: Vec<VariantCheckOutput> = abi_output
            .variants
            .iter()
            .map(|v| VariantCheckOutput {
                name: v.name.clone(),
                compatible: v.is_compatible,
                has_shared_objects: v.has_shared_objects,
                violations: v
                    .violations
                    .iter()
                    .map(|viol| viol.message.clone())
                    .collect(),
            })
            .collect();

        let result = RepositoryCheckResult {
            repository: repo_id.to_string(),
            status: "success".to_string(),
            build_status: BuildStatus {
                summary: build_status,
                cuda: cuda_status,
                rocm: rocm_status,
            },
            abi_status: AbiStatus {
                compatible: abi_output.overall_compatible,
                manylinux_version: abi_output.manylinux_version.clone(),
                python_abi_version: abi_output.python_abi_version.to_string(),
                variants: variant_outputs,
            },
        };

        // Output pretty-printed JSON
        println!(
            "{}",
            serde_json::to_string_pretty(&result).context("Failed to serialize result")?
        );
    } else {
        // Display console-formatted output via ConsoleFormatter
        ConsoleFormatter::format_repository_check_result(
            repo_id,
            &build_status,
            cuda_compatible,
            rocm_compatible,
            &COMPLIANT_VARIANTS.0,
            &COMPLIANT_VARIANTS.1,
            cuda_variants_present_set,
            rocm_variants_present_set,
            compact_output,
            &abi_output,
            abi_status,
        );
    }

    Ok(())
}

/// Check if the specified revision in a repository needs processing
pub fn check_repository_revision(
    repo_id: &str,
    cache_dir: &Path,
    revision: &str,
    format: Format,
) -> Result<(bool, PathBuf, String)> {
    let repo_path = get_repo_path(repo_id, cache_dir);
    let ref_path = repo_path.join("refs").join(revision);

    // Check if repository exists with specified revision
    if !repo_path.exists() || !ref_path.exists() {
        if !format.is_json() {
            println!(
                "Repository {} with revision {} not found locally",
                repo_id, revision
            );
        }
        return Ok((false, PathBuf::new(), String::new()));
    }

    // Read hash from revision file
    let hash = fs::read_to_string(&ref_path)
        .with_context(|| format!("Failed to read ref file: {:?}", ref_path))?
        .trim()
        .to_string();

    // Check if snapshot exists
    let snapshot_dir = repo_path.join("snapshots").join(&hash);
    if !snapshot_dir.exists() {
        if !format.is_json() {
            println!(
                "Snapshot for hash {} not found in repository {}",
                hash, repo_id
            );
        }
        return Ok((false, PathBuf::new(), String::new()));
    }

    Ok((true, snapshot_dir, hash))
}
