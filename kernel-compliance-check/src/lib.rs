mod formatter;
mod models;

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use eyre::{Context, Result};
use futures::stream::{self, StreamExt};
use hf_hub::api::tokio::{ApiBuilder, ApiError};
use hf_hub::{Cache, Repo, RepoType};
use kernel_abi_check::{check_manylinux, check_python_abi, Version};
use object::Object;

pub use formatter::Console;
pub use models::*;

pub use models::{AbiCheckResult, Cli, Commands, CompliantError, Format, Variant};

// Get the build variants the parent directory, starting from the app dir
static BUILD_VARIANTS: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../build_variants.json"
));

/// Returns a list of available CUDA variants from build configuration
#[must_use]
pub fn get_cuda_variants() -> Vec<String> {
    serde_json::from_str::<HashMap<String, HashMap<String, Vec<String>>>>(BUILD_VARIANTS)
        .map(|variants| {
            variants
                .values()
                .filter_map(|arch_data| arch_data.get("cuda"))
                .flat_map(std::clone::Clone::clone)
                .collect()
        })
        .unwrap_or_default()
}

/// Returns a list of available `ROCm` variants from build configuration
#[must_use]
pub fn get_rocm_variants() -> Vec<String> {
    serde_json::from_str::<HashMap<String, HashMap<String, Vec<String>>>>(BUILD_VARIANTS)
        .map(|variants| {
            variants
                .values()
                .filter_map(|arch_data| arch_data.get("rocm"))
                .flat_map(std::clone::Clone::clone)
                .collect()
        })
        .unwrap_or_default()
}

#[allow(clippy::too_many_lines)]
async fn fetch_repository_async(
    repo_id: &str,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
) -> Result<()> {
    eprintln!("Repository: {repo_id} (revision: {revision})");

    // Create API client
    let api = ApiBuilder::from_env()
        .high()
        .build()
        .context("Failed to create HF API client")?;

    let repo = Repo::with_revision(repo_id.to_string(), RepoType::Model, revision.to_string());

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

        eprintln!("Using huggingface-cli to download repository");

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
                    println!("{line}");
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
                    eprintln!("{line}"); // Print to stderr
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
                "Failed to download repository {repo_id}: {stderr_output}"
            ))
            .into());
        }

        eprintln!("Downloaded repository successfully using huggingface-cli");
        return Ok(());
    }

    // If here use the API to download the repository (fallback)
    eprintln!("Using API to download repository");

    let api_repo = api.repo(repo);
    // Get repository info and file list
    let info = api_repo
        .info()
        .await
        .context(format!("Failed to fetch repo info for {repo_id}"))?;

    let file_names = info
        .siblings
        .iter()
        .map(|f| f.rfilename.clone())
        .collect::<Vec<_>>();

    // Download files
    eprintln!("Starting download of {} files", file_names.len());

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
                                eprintln!(
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
                                return Err(eyre::eyre!(
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
                eprintln!("{e}");
            }
        }
        // Only return an error if all downloads failed
        if success_count == 0 {
            return Err(CompliantError::FetchError(format!(
                "All {fail_count} downloads failed for repository {repo_id}"
            ))
            .into());
        }
    }

    // Log success info
    if force_fetch {
        eprintln!("Force fetched {success_count} files successfully ({fail_count} failed)");
    } else {
        eprintln!("Downloaded {success_count} files successfully ({fail_count} failed)");
    }

    Ok(())
}

/// Synchronous wrapper for the async fetch repository function
///
/// # Errors
/// Returns an error if the repository fetch fails or if the Tokio runtime cannot be created
pub fn fetch_repository(
    repo_id: &str,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
) -> Result<()> {
    if force_fetch {
        eprintln!("Force fetch (redownloading all files)");
    } else {
        eprintln!("Syncing (checking for updates)");
    }

    let rt = tokio::runtime::Runtime::new().context("Failed to create Tokio runtime")?;
    rt.block_on(fetch_repository_async(
        repo_id,
        revision,
        force_fetch,
        prefer_hub_cli,
    ))
}

/// Checks if there is a valid, up-to-date snapshot directory for the repository
///
/// # Errors
/// Returns an error if the metadata cannot be fetched or if the directory path is invalid
pub fn snapshot_dir_if_latest(
    api: &hf_hub::api::tokio::Api,
    repo: &Repo,
) -> Result<Option<PathBuf>> {
    let metadata = {
        let rt = tokio::runtime::Runtime::new().context("failed to create Tokio runtime")?;
        let api_repo = api.repo(repo.clone());
        rt.block_on(api_repo.info())
            .context("failed to fetch metadata")?
    };

    let sha_on_hub = &metadata.sha;
    let Some(first_item) = metadata.siblings.first() else {
        return Ok(None);
    }; // nothing published yet

    let cache = Cache::from_env();
    let cached_repo = cache.repo(repo.clone());

    let Some(file) = cached_repo.get(&first_item.rfilename) else {
        return Ok(None);
    }; // file not cached

    if !file.to_string_lossy().contains(sha_on_hub) {
        return Ok(None); // outdated snapshot
    }

    file.parent()
        .map(std::path::Path::to_path_buf)
        .ok_or_else(|| {
            CompliantError::BuildDirNotFound(format!(
                "Failed to get parent directory for file: {file:?}"
            ))
        })
        .map(Some)
        .context("failed to get snapshot directory")
}

/// Processes a repository by fetching it if needed and checking its compatibility
///
/// # Errors
/// Returns an error if the repository cannot be fetched or processed
#[allow(clippy::too_many_arguments)]
#[allow(clippy::fn_params_excessive_bools)]
pub fn process_repository(
    repo_id: &str,
    revision: &str,
    force_fetch: bool,
    prefer_hub_cli: bool,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
    non_standard_cache: Option<&String>,
) -> Result<()> {
    let api = {
        let mut builder = ApiBuilder::from_env().high();

        if let Some(cache_dir) = non_standard_cache {
            builder = builder.with_cache_dir(PathBuf::from(cache_dir));
        }

        builder.build().wrap_err("failed to create HF API client")?
    };

    let repo = Repo::with_revision(repo_id.to_owned(), RepoType::Model, revision.to_owned());

    // Check for existing snapshot directory
    if !force_fetch {
        if let Some(dir) = snapshot_dir_if_latest(&api, &repo)? {
            return process_repository_snapshot(
                repo_id,
                &dir,
                manylinux,
                python_version,
                compact_output,
                show_violations,
                format,
            );
        }
        eprintln!("No valid snapshot directory found");
    }

    // Fetch the repository
    if !format.is_json() {
        Console::format_fetch_status(repo_id, true, None);
    }

    if let Err(e) = fetch_repository(repo_id, revision, force_fetch, prefer_hub_cli) {
        return Err(CompliantError::FetchError(format!(
            "failed to fetch repository {repo_id}: {e}"
        ))
        .into());
    }

    if !format.is_json() {
        Console::format_fetch_status(repo_id, false, Some("fetch successful"));
    }

    // Recheck repository after fetch
    match snapshot_dir_if_latest(&api, &repo)? {
        Some(dir) => process_repository_snapshot(
            repo_id,
            &dir,
            manylinux,
            python_version,
            compact_output,
            show_violations,
            format,
        ),
        None => Err(CompliantError::RepositoryNotFound(format!(
            "repository {repo_id} not found after fetch"
        ))
        .into()),
    }
}

/// Gets all build variants from a repository
///
/// # Errors
/// Returns an error if the build directory cannot be read
pub fn get_build_variants(repo_path: &Path) -> Result<Vec<Variant>> {
    let build_dir = repo_path.join("build");
    let mut variants = Vec::new();

    if !build_dir.exists() {
        return Ok(variants);
    }

    let entries = fs::read_dir(&build_dir)
        .with_context(|| format!("Failed to read build directory: {build_dir:?}"))?;

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
#[must_use]
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
        format!("Total: {built} (CUDA: {cuda_built})")
    }
}

/// Recursively finds all shared object files in a directory
///
/// # Errors
/// Returns an error if the directory cannot be read
pub fn find_shared_objects(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut so_files = Vec::new();

    if !dir.exists() || !dir.is_dir() {
        return Ok(so_files);
    }

    let entries =
        fs::read_dir(dir).with_context(|| format!("Failed to read directory: {dir:?}"))?;

    for entry in entries {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();

        if path.is_dir() {
            let mut subdir_so_files = find_shared_objects(&path)
                .with_context(|| format!("Failed to find .so files in subdirectory: {path:?}"))?;
            so_files.append(&mut subdir_so_files);
        } else if let Some(extension) = path.extension() {
            if extension == "so" {
                so_files.push(path);
            }
        }
    }

    Ok(so_files)
}

/// Checks if a shared object is compatible with the given manylinux and Python ABI versions
///
/// # Errors
/// Returns an error if the shared object cannot be read or analyzed
pub fn check_shared_object(
    so_path: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    show_violations: bool,
) -> Result<(bool, String)> {
    let mut violations_output = String::new();

    // Read binary data
    let binary_data = fs::read(so_path)
        .with_context(|| format!("Failed to read shared object file: {so_path:?}"))?;

    // Parse object file
    let file = object::File::parse(&*binary_data)
        .with_context(|| format!("Failed to parse shared object file: {so_path:?}"))?;

    // Run manylinux check
    let manylinux_result = check_manylinux(
        manylinux_version,
        file.architecture(),
        file.endianness(),
        file.symbols(),
    )
    .with_context(|| format!("Failed to check manylinux compatibility: {so_path:?}"))?;

    // Run Python ABI check
    let python_abi_result = check_python_abi(python_abi_version, file.symbols())
        .with_context(|| format!("Failed to check Python ABI compatibility: {so_path:?}"))?;

    // Determine if checks passed
    let passed = manylinux_result.is_empty() && python_abi_result.is_empty();

    // Generate violations output if requested
    if !passed && show_violations {
        if !manylinux_result.is_empty() {
            violations_output.push_str("\n  manylinux violations:\n");
            for violation in &manylinux_result {
                violations_output.push_str(&format!("    - {violation:?}\n"));
            }
        }

        if !python_abi_result.is_empty() {
            violations_output.push_str("\n  python abi violations:\n");
            for violation in &python_abi_result {
                violations_output.push_str(&format!("    - {violation:?}\n"));
            }
        }
    }

    Ok((passed, violations_output))
}

/// Checks ABI compatibility for all variants in a repository
///
/// # Errors
/// Returns an error if the repository cannot be analyzed
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
        .with_context(|| format!("Failed to read build directory: {build_dir:?}"))?;

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
    for variant_path in &variant_paths {
        let variant_name = variant_path
            .file_name()
            .ok_or_else(|| {
                CompliantError::Other(format!("Invalid variant path: {variant_path:?}"))
            })?
            .to_string_lossy()
            .to_string();

        let so_files = find_shared_objects(variant_path)
            .with_context(|| format!("Failed to find shared objects in variant: {variant_name}"))?;

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
            .with_context(|| format!("Failed to check shared object: {so_path:?}"))?;

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

/// Processes a repository snapshot once we have it
///
/// # Errors
/// Returns an error if the repository snapshot cannot be processed
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_lines)]
pub fn process_repository_snapshot(
    repo_id: &str,
    snapshot_dir: &Path,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
) -> Result<()> {
    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        // Print a message indicating the build directory is missing
        if format.is_json() {
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
        } else {
            return Err(CompliantError::BuildDirNotFound(repo_id.to_string()).into());
        }

        return Err(CompliantError::BuildDirNotFound(repo_id.to_string()).into());
    }

    let variants = get_build_variants(snapshot_dir).context("Failed to get build variants")?;
    let variant_strings: Vec<String> = variants
        .iter()
        .map(std::string::ToString::to_string)
        .collect();

    let build_status = get_build_status_summary(
        &build_dir,
        &variant_strings,
        &get_cuda_variants(),
        &get_rocm_variants(),
    );

    let abi_output =
        check_abi_for_repository(snapshot_dir, manylinux, python_version, show_violations)
            .with_context(|| format!("Failed to check ABI compatibility for {repo_id}"))?;

    let abi_status = if abi_output.overall_compatible {
        "compatible"
    } else {
        "incompatible"
    };

    // Get present CUDA and ROCM variants
    let cuda_variants_present_set: Vec<String> = get_cuda_variants()
        .iter()
        .filter(|v| variant_strings.contains(v))
        .cloned()
        .collect();

    #[cfg(feature = "enable_rocm")]
    let rocm_variants_present_set: Vec<&String> = get_rocm_variants()
        .iter()
        .filter(|v| variant_strings.contains(v))
        .collect();

    #[cfg(not(feature = "enable_rocm"))]
    let rocm_variants_present_set: Vec<String> = Vec::new();

    // Check if all required variants are present
    let cuda_compatible = cuda_variants_present_set.len() == get_cuda_variants().len();

    #[cfg(feature = "enable_rocm")]
    let rocm_compatible = rocm_variants_present_set.len() == get_rocm_variants().len();

    #[cfg(not(feature = "enable_rocm"))]
    let rocm_compatible = true; // When ROCm is disabled, consider it compatible but unused

    if format.is_json() {
        // Create structured data for JSON output
        let cuda_status = CudaStatus {
            compatible: cuda_compatible,
            present: cuda_variants_present_set.clone(),
            missing: get_cuda_variants()
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
                .map(|v| v.clone())
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
        // Display console-formatted output via Console
        Console::format_repository_check_result(
            repo_id,
            &build_status,
            cuda_compatible,
            rocm_compatible,
            &get_cuda_variants(),
            &get_rocm_variants(),
            &cuda_variants_present_set,
            rocm_variants_present_set,
            compact_output,
            &abi_output,
            abi_status,
        );
    }

    Ok(())
}
