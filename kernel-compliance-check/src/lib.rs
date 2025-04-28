use anyhow::{Context, Result};
use clap::{Parser, Subcommand, ValueEnum};
use colored::Colorize;
use hf_hub::api::tokio::{ApiBuilder, ApiError};
use hf_hub::{Repo, RepoType};
use kernel_abi_check::{check_manylinux, check_python_abi, Version};
use object::Object;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CompliantError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Repository not found: {0}")]
    RepositoryNotFound(String),

    #[error("Build directory not found in repository: {0}")]
    BuildDirNotFound(String),

    #[error("Failed to fetch repository: {0}")]
    FetchError(String),

    #[error("Failed to parse object file: {0}")]
    ObjectParseError(String),

    #[error("Failed to check ABI compatibility: {0}")]
    AbiCheckError(String),

    #[error("Failed to serialize JSON: {0}")]
    SerializationError(String),

    #[error("Failed to fetch variants: {0}")]
    VariantsFetchError(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Unknown error: {0}")]
    Other(String),
}

/// Hugging Face kernel compliance checker
#[derive(Parser)]
#[command(author, version, about)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Format {
    Console,
    Json,
}

impl Format {
    pub fn is_json(&self) -> bool {
        matches!(self, Format::Json)
    }
}

#[derive(Subcommand)]
pub enum Commands {
    /// List fetched repositories with build variants
    List {
        /// Format of the output. Default is console
        #[arg(long, default_value = "console")]
        format: Format,
    },

    /// Check repository compliance and ABI compatibility
    Check {
        /// Repository IDs or names (comma-separated)
        #[arg(short, long)]
        repos: String,

        /// Manylinux version to check against
        #[arg(short, long, default_value = "manylinux_2_28")]
        manylinux: String,

        /// Python ABI version to check against
        #[arg(short, long, default_value = "3.9")]
        python_abi: String,

        /// Automatically fetch repositories if not found locally
        #[arg(short, long, default_value = "true")]
        auto_fetch: bool,

        /// Revision (branch, tag, or commit hash) to use when fetching
        #[arg(short, long, default_value = "main")]
        revision: String,

        /// Show all variants in a long format. Default is compact output.
        #[arg(long, default_value = "false")]
        long: bool,

        /// Show ABI violations in the output. Default is to only show compatibility status.
        #[arg(long, default_value = "false")]
        show_violations: bool,

        /// Format of the output. Default is console
        #[arg(long, default_value = "console")]
        format: Format,
    },
}

/// Structured representation of build variants
#[derive(Debug, Deserialize)]
struct VariantsConfig {
    #[serde(rename = "x86_64-linux")]
    x86_64_linux: ArchConfig,
    #[serde(rename = "aarch64-linux")]
    aarch64_linux: ArchConfig,
}

#[derive(Debug, Deserialize)]
struct ArchConfig {
    cuda: Vec<String>,
    #[serde(default)]
    #[cfg(feature = "enable_rocm")]
    rocm: Vec<String>,
    #[cfg(not(feature = "enable_rocm"))]
    #[serde(default, skip)]
    _rocm: Vec<String>,
}

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

/// Synchronous wrapper for fetching variants. This avoids spreading async/await throughout
/// the codebase. Used for compatibility with sync contexts.
fn fetch_variants_sync() -> Result<(Vec<String>, Vec<String>)> {
    let rt = tokio::runtime::Runtime::new().context("Failed to create Tokio runtime")?;
    rt.block_on(fetch_compliant_variants())
}

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variant {
    torch_version: String,
    cxx_abi: String,
    compute_framework: String,
    arch: String,
    os: String,
}

impl fmt::Display for Variant {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}-{}-{}-{}-{}",
            self.torch_version, self.cxx_abi, self.compute_framework, self.arch, self.os
        )
    }
}

impl Variant {
    pub fn from_name(name: &str) -> Option<Self> {
        let parts: Vec<&str> = name.split('-').collect();
        if parts.len() < 5 {
            return None;
        }
        // Format: torch{major}{minor}-{cxxabi}-{compute_framework}-{arch}-{os}
        Some(Variant {
            torch_version: parts[0].to_string(),
            cxx_abi: parts[1].to_string(),
            compute_framework: parts[2].to_string(),
            arch: parts[3].to_string(),
            os: parts[4].to_string(),
        })
    }
}

/// Struct to hold repository list result
#[derive(Serialize)]
pub struct RepoListResult {
    pub repositories: Vec<String>,
    pub count: usize,
}

/// Struct for console output formatting
pub struct ConsoleFormatter;

impl ConsoleFormatter {
    pub fn format_repo_list(repos: &[String], count: usize) {
        println!(".");
        for repo_id in repos {
            println!("├── {}", repo_id);
        }
        println!("╰── {} kernel repositories found\n", count);
    }

    pub fn format_missing_repo(repo_id: &str) {
        println!(".");
        println!("├── {}", repo_id.on_bright_white().black().bold());
        println!("├── build: missing");
        println!("╰── abi: missing");
    }

    pub fn format_fetch_status(repo_id: &str, fetching: bool, result: Option<&str>) {
        println!("repository: {}", repo_id);
        if fetching {
            println!("status: not found locally, fetching...");
        }
        if let Some(message) = result {
            println!("status: {}", message);
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn format_repository_check_result(
        repo_id: &str,
        build_status: &str,
        cuda_compatible: bool,
        #[cfg(feature = "enable_rocm")] rocm_compatible: bool,
        #[cfg(not(feature = "enable_rocm"))] _rocm_compatible: bool,
        cuda_variants: &[String],
        #[cfg(feature = "enable_rocm")] rocm_variants: &[String],
        #[cfg(not(feature = "enable_rocm"))] _rocm_variants: &[String],
        cuda_variants_present: Vec<&String>,
        #[cfg(feature = "enable_rocm")] rocm_variants_present: Vec<&String>,
        #[cfg(not(feature = "enable_rocm"))] _rocm_variants_present: Vec<&String>,
        compact_output: bool,
        abi_output: &AbiCheckResult,
        abi_status: &str,
    ) {
        // Display console-formatted output
        let abi_mark = if abi_output.overall_compatible {
            "✓".green()
        } else {
            "✗".red()
        };

        let cuda_mark = if cuda_compatible {
            "✓".green()
        } else {
            "✗".red()
        };

        #[cfg(feature = "enable_rocm")]
        let rocm_mark = if rocm_compatible {
            "✓".green()
        } else {
            "✗".red()
        };

        let label = format!(" {} ", repo_id).black().on_bright_white().bold();

        println!("\n{}", label);
        println!("├── build: {}", build_status);

        if !compact_output {
            println!("│  {} {}", cuda_mark, "CUDA".bold());

            // Print variant list with proper tree characters
            for (i, cuda_variant) in cuda_variants.iter().enumerate() {
                let is_last = i == cuda_variants.len() - 1;
                let is_present = cuda_variants_present.contains(&cuda_variant);
                let prefix = if is_last {
                    "│    ╰── "
                } else {
                    "│    ├── "
                };

                if is_present {
                    println!("{}{}", prefix, cuda_variant);
                } else {
                    println!("{}{}", prefix, cuda_variant.dimmed());
                }
            }

            // Only show ROCm section if the feature is enabled
            #[cfg(feature = "enable_rocm")]
            {
                println!("│  {} {}", rocm_mark, "ROCM".bold());

                for (i, rocm_variant) in rocm_variants.iter().enumerate() {
                    let is_last = i == rocm_variants.len() - 1;
                    let is_present = rocm_variants_present.contains(&rocm_variant);
                    let prefix = if is_last {
                        "│    ╰── "
                    } else {
                        "│    ├── "
                    };

                    if is_present {
                        println!("{}{}", prefix, rocm_variant);
                    } else {
                        println!("{}{}", prefix, rocm_variant.dimmed());
                    }
                }
            }
        } else {
            // Compact output
            #[cfg(feature = "enable_rocm")]
            {
                println!("│   ├── {} CUDA", cuda_mark);
                println!("│   ╰── {} ROCM", rocm_mark);
            }

            #[cfg(not(feature = "enable_rocm"))]
            {
                println!("│   ╰── {} CUDA", cuda_mark);
            }
        }

        // ABI status section
        println!("╰── abi: {}", abi_status);
        println!("    ├── {} {}", abi_mark, abi_output.manylinux_version);
        println!(
            "    ╰── {} python {}",
            abi_mark, abi_output.python_abi_version
        );
    }
}

#[derive(Serialize)]
pub struct RepoErrorResponse {
    repository: String,
    status: String,
    error: String,
}

#[derive(Serialize)]
pub struct RepositoryCheckResult {
    repository: String,
    status: String,
    build_status: BuildStatus,
    abi_status: AbiStatus,
}

#[derive(Serialize)]
pub struct BuildStatus {
    summary: String,
    cuda: CudaStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    rocm: Option<RocmStatus>,
}

#[derive(Serialize)]
pub struct CudaStatus {
    compatible: bool,
    present: Vec<String>,
    missing: Vec<String>,
}

#[derive(Serialize)]
pub struct RocmStatus {
    compatible: bool,
    present: Vec<String>,
    missing: Vec<String>,
}

#[derive(Serialize)]
pub struct AbiStatus {
    compatible: bool,
    manylinux_version: String,
    python_abi_version: String,
    variants: Vec<VariantCheckOutput>,
}

#[derive(Serialize)]
pub struct VariantCheckOutput {
    name: String,
    compatible: bool,
    has_shared_objects: bool,
    violations: Vec<String>,
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

pub async fn fetch_repository_async(repo_id: &str, revision: &str) -> Result<()> {
    let api = ApiBuilder::new()
        .high()
        .build()
        .context("Failed to create HF API client")?;

    let repo = Repo::with_revision(repo_id.to_string(), RepoType::Model, revision.to_string());

    let api_repo = api.repo(repo);
    let info = api_repo
        .info()
        .await
        .context(format!("Failed to fetch repo info for {}", repo_id))?;

    let file_names = info
        .siblings
        .iter()
        .map(|f| f.rfilename.clone())
        .collect::<Vec<_>>();

    // Create a stream of tasks and process them concurrently with bounded parallelism
    use futures::stream::{self, StreamExt};

    let download_results = stream::iter(file_names)
        .map(|file_name| {
            // Create a new API instance for each download to avoid shared state issues
            let api = ApiBuilder::new().high().build().unwrap();
            let repo_clone =
                Repo::with_revision(repo_id.to_string(), RepoType::Model, revision.to_string());
            let download_repo = api.repo(repo_clone);
            let file_to_download = file_name.clone();

            async move {
                if let Err(e) = download_repo.download(&file_name).await {
                    // Special case for __init__.py which can be empty
                    if file_name.contains("__init__.py") && matches!(e, ApiError::RequestError(_)) {
                        return Ok(file_name);
                    }

                    Err(anyhow::anyhow!("Failed to download {}: {}", file_name, e))
                } else {
                    Ok(file_to_download)
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
    println!(
        "Downloaded {} files successfully ({} failed)",
        success_count, fail_count
    );

    Ok(())
}

/// Synchronous wrapper for the async fetch repository function
pub fn fetch_repository(repo_id: &str, _cache_dir: &Path, revision: &str) -> Result<()> {
    println!("fetching: {} (revision: {})", repo_id, revision);

    let rt = tokio::runtime::Runtime::new().context("Failed to create Tokio runtime")?;

    rt.block_on(fetch_repository_async(repo_id, revision))
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedObjectViolation {
    pub message: String,
    // TODO: Explore what other fields we may need
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariantResult {
    pub name: String,
    pub is_compatible: bool,
    pub violations: Vec<SharedObjectViolation>,
    pub has_shared_objects: bool,
}

#[derive(Debug, Clone)]
pub struct AbiCheckResult {
    pub overall_compatible: bool,
    pub variants: Vec<VariantResult>,
    pub manylinux_version: String,
    pub python_abi_version: Version,
}

impl Serialize for AbiCheckResult {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut state = serializer.serialize_struct("AbiCheckResult", 4)?;
        state.serialize_field("overall_compatible", &self.overall_compatible)?;
        state.serialize_field("variants", &self.variants)?;
        state.serialize_field("manylinux_version", &self.manylinux_version)?;
        state.serialize_field("python_abi_version", &self.python_abi_version.to_string())?;
        state.end()
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

#[allow(clippy::too_many_arguments)]
pub fn process_repository(
    repo_id: &str,
    cache_dir: &Path,
    revision: &str,
    auto_fetch: bool,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
) -> Result<()> {
    let repo_path = get_repo_path(repo_id, cache_dir);

    // Check if repository exists locally
    if !repo_path.exists() || !repo_path.join("refs/main").exists() {
        if auto_fetch {
            if !format.is_json() {
                ConsoleFormatter::format_fetch_status(repo_id, true, None);
            }

            // Fetch the repository
            match fetch_repository(repo_id, cache_dir, revision) {
                Ok(_) => {
                    if !format.is_json() {
                        ConsoleFormatter::format_fetch_status(
                            repo_id,
                            false,
                            Some("fetch successful"),
                        );
                    }
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
                    return Ok(());
                }
            }
        } else {
            // Print a message indicating the repository is missing
            if !format.is_json() {
                ConsoleFormatter::format_missing_repo(repo_id);
            } else {
                let error = RepoErrorResponse {
                    repository: repo_id.to_string(),
                    status: "not_found".to_string(),
                    error: "repository not found locally".to_string(),
                };
                println!(
                    "{}",
                    serde_json::to_string_pretty(&error)
                        .context("Failed to serialize error response")?
                );
            }

            return Err(CompliantError::RepositoryNotFound(repo_id.to_string()).into());
        }
    }

    // Re-check after potential fetch
    let ref_file = repo_path.join("refs/main");
    if !ref_file.exists() {
        // Print a message indicating the repository is missing
        if !format.is_json() {
            ConsoleFormatter::format_missing_repo(repo_id);
        } else {
            let error = RepoErrorResponse {
                repository: repo_id.to_string(),
                status: "not_found".to_string(),
                error: "repository not found locally".to_string(),
            };
            println!(
                "{}",
                serde_json::to_string_pretty(&error)
                    .context("Failed to serialize error response")?
            );
        }

        return Err(CompliantError::RepositoryNotFound(repo_id.to_string()).into());
    }

    let content = fs::read_to_string(&ref_file)
        .with_context(|| format!("Failed to read ref file: {:?}", ref_file))?;

    let hash = content.trim();
    let snapshot_dir = repo_path.join(format!("snapshots/{}", hash));

    if !snapshot_dir.exists() {
        // Print a message indicating the snapshot is missing
        if !format.is_json() {
            ConsoleFormatter::format_missing_repo(repo_id);
        } else {
            let error = RepoErrorResponse {
                repository: repo_id.to_string(),
                status: "missing_snapshot".to_string(),
                error: "snapshot not found".to_string(),
            };
            println!(
                "{}",
                serde_json::to_string_pretty(&error)
                    .context("Failed to serialize error response")?
            );
        }

        return Err(CompliantError::RepositoryNotFound(format!(
            "Snapshot not found for repository {}",
            repo_id
        ))
        .into());
    }

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

    let variants = get_build_variants(&snapshot_dir).context("Failed to get build variants")?;

    let variant_strings: Vec<String> = variants.iter().map(|v| v.to_string()).collect();

    let build_status = get_build_status_summary(
        &build_dir,
        &variant_strings,
        &COMPLIANT_VARIANTS.0,
        &COMPLIANT_VARIANTS.1,
    );

    let abi_output =
        check_abi_for_repository(&snapshot_dir, manylinux, python_version, show_violations)
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
