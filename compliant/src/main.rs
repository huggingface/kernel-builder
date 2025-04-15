use clap::{Parser, Subcommand};
use colored::Colorize;
use hf_hub::{Repo, RepoType};
use kernel_abi_check::{check_manylinux, check_python_abi, Version};
use object::Object;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;

/// Hugging Face kernel compliance checker
#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
enum Format {
    Console,
    Json,
}

#[derive(Subcommand)]
enum Commands {
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

const CUDA_COMPLIANT_VARIANTS: [&str; 12] = [
    "torch25-cxx11-cu118-x86_64-linux",
    "torch25-cxx11-cu121-x86_64-linux",
    "torch25-cxx11-cu124-x86_64-linux",
    "torch25-cxx98-cu118-x86_64-linux",
    "torch25-cxx98-cu121-x86_64-linux",
    "torch25-cxx98-cu124-x86_64-linux",
    "torch26-cxx11-cu118-x86_64-linux",
    "torch26-cxx11-cu124-x86_64-linux",
    "torch26-cxx11-cu126-x86_64-linux",
    "torch26-cxx98-cu118-x86_64-linux",
    "torch26-cxx98-cu124-x86_64-linux",
    "torch26-cxx98-cu126-x86_64-linux",
];

const ROCM_COMPLIANT_VARIANTS: [&str; 7] = [
    "torch25-cxx11-rocm5.4-x86_64-linux",
    "torch25-cxx11-rocm5.6-x86_64-linux",
    "torch25-cxx98-rocm5.4-x86_64-linux",
    "torch25-cxx98-rocm5.6-x86_64-linux",
    "torch26-cxx11-rocm5.4-x86_64-linux",
    "torch26-cxx11-rocm5.6-x86_64-linux",
    "torch26-cxx11-rocm62-x86_64-linux", // MAY NEED TO BE REMOVED
];

#[derive(Debug, Clone)]
struct Variant {
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
    fn from_name(name: &str) -> Option<Self> {
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

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let cache_dir = get_cache_dir()?;

    match cli.command {
        Commands::List { format } => {
            let entries = fs::read_dir(&cache_dir)?;
            let mut found_repos = 0;
            let mut repo_list = Vec::new();

            for entry in entries {
                let entry = entry?;
                let path = entry.path();

                if !path.is_dir() {
                    continue;
                }

                // Extract repo ID from path
                let repo_id = get_repo_id_from_path(&path)?;

                // Check if this repo has a build directory with variants
                if has_build_variants(&path)? {
                    repo_list.push(repo_id);
                    found_repos += 1;
                }
            }

            // Sort repositories for consistent display
            repo_list.sort();

            if format == Format::Json {
                // Create JSON response
                let json_output = serde_json::json!({
                    "repositories": repo_list,
                    "count": found_repos
                });

                println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
            } else {
                println!(".");
                for repo_id in repo_list {
                    println!("├── {}", repo_id);
                }
                println!("╰── {} kernel repositories found\n", found_repos);
            }
        }

        Commands::Check {
            repos,
            manylinux,
            python_abi,
            auto_fetch,
            revision,
            long,
            show_violations,
            format,
        } => {
            let repositories: Vec<String> = repos
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();

            if repositories.is_empty() {
                if format == Format::Json {
                    let json_output = serde_json::json!({
                        "status": "error",
                        "error": "no repository ids provided"
                    });
                    println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
                } else {
                    eprintln!("no repository ids provided");
                }
                return Ok(());
            }

            let python_version = Version::from_str(&python_abi).map_err(|e| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    format!("invalid python abi version: {}", e),
                )
            })?;

            for repo_id in &repositories {
                process_repository(
                    repo_id,
                    &cache_dir,
                    &revision,
                    auto_fetch,
                    &manylinux,
                    &python_version,
                    !long,
                    show_violations,
                    format,
                )?;
            }
        }
    }
    Ok(())
}

// Get "org/name" repo ID from filesystem path
fn get_repo_id_from_path(path: &Path) -> Result<String, Box<dyn std::error::Error>> {
    // Extract the organization and model name from the path
    let dir_name = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    // Remove the "models--" prefix if present
    let dir_name = dir_name
        .strip_prefix("models--")
        .unwrap_or(&dir_name)
        .replace("--", "/");

    Ok(dir_name)
}

// Check if repository has build variants
fn has_build_variants(repo_path: &Path) -> Result<bool, Box<dyn std::error::Error>> {
    // Look for the snapshot directory
    let ref_file = repo_path.join("refs/main");
    if !ref_file.exists() {
        return Ok(false);
    }

    let content = fs::read_to_string(ref_file)?;
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
    let entries = fs::read_dir(&build_dir)?;
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            // At least one build variant exists
            return Ok(true);
        }
    }

    // Build directory exists but is empty
    Ok(false)
}

#[allow(clippy::too_many_arguments)]
fn process_repository(
    repo_id: &str,
    cache_dir: &Path,
    revision: &str,
    auto_fetch: bool,
    manylinux: &str,
    python_version: &Version,
    compact_output: bool,
    show_violations: bool,
    format: Format,
) -> Result<(), Box<dyn std::error::Error>> {
    let repo_path = get_repo_path(repo_id, cache_dir);

    // Check if repository exists locally
    if !repo_path.exists() || !repo_path.join("refs/main").exists() {
        if auto_fetch {
            if format == Format::Console {
                println!("repository: {}", repo_id);
                println!("status: not found locally, fetching...");
            }

            // Fetch the repository
            match fetch_repository(repo_id, cache_dir, revision) {
                Ok(_) => {
                    if format == Format::Console {
                        println!("status: fetch successful");
                    }
                }
                Err(e) => {
                    if format == Format::Console {
                        println!("status: fetch failed - {}", e);
                        println!("---");
                    } else {
                        let json_output = serde_json::json!({
                            "repository": repo_id,
                            "status": "fetch_failed",
                            "error": e.to_string()
                        });
                        println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
                    }
                    return Ok(());
                }
            }
        } else {
            // Print a message indicating the repository is missing
            if format == Format::Console {
                println!(".");
                println!("├── {}", repo_id.on_bright_white().black().bold());
                println!("├── build: missing");
                println!("╰── abi: missing");
            } else {
                let json_output = serde_json::json!({
                    "repository": repo_id,
                    "status": "not_found",
                    "error": "repository not found locally"
                });
                println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
            }

            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "repository not found locally",
            )));
        }
    }

    // Re-check after potential fetch
    let ref_file = repo_path.join("refs/main");
    if !ref_file.exists() {
        // Print a message indicating the repository is missing
        if format == Format::Console {
            println!(".");
            println!("├── {}", repo_id.on_bright_white().black().bold());
            println!("├── build: missing");
            println!("╰── abi: missing");
        } else {
            let json_output = serde_json::json!({
                "repository": repo_id,
                "status": "not_found",
                "error": "repository not found locally"
            });
            println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
        }

        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "repository not found locally",
        )));
    }

    let content = fs::read_to_string(ref_file)?;
    let hash = content.trim();
    let snapshot_dir = repo_path.join(format!("snapshots/{}", hash));

    if !snapshot_dir.exists() {
        // Print a message indicating the snapshot is missing
        if format == Format::Console {
            println!(".");
            println!("├── {}", repo_id.on_bright_white().black().bold());
            println!("├── build: missing");
            println!("╰── abi: missing");
        } else {
            let json_output = serde_json::json!({
                "repository": repo_id,
                "status": "missing_snapshot",
                "error": "snapshot not found"
            });
            println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
        }

        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "snapshot not found",
        )));
    }

    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        // Print a message indicating the build directory is missing
        if format == Format::Console {
            println!(".");
            println!("├── {}", repo_id.on_bright_white().black().bold());
            println!("├── build: missing");
            println!("╰── abi: missing");
        } else {
            let json_output = serde_json::json!({
                "repository": repo_id,
                "status": "missing_build_dir",
                "error": "build directory not found"
            });
            println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
        }

        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "build directory not found",
        )));
    }

    let variants = get_build_variants(&snapshot_dir)?;
    let build_status = get_build_status_summary(
        &build_dir,
        variants
            .iter()
            .map(|v| v.to_string())
            .collect::<Vec<_>>()
            .as_slice(),
        &CUDA_COMPLIANT_VARIANTS,
        &ROCM_COMPLIANT_VARIANTS,
    );

    let abi_output =
        check_abi_for_repository(&snapshot_dir, manylinux, python_version, show_violations)?;

    let abi_status = if abi_output.overall_compatible {
        "compatible"
    } else {
        "incompatible"
    };

    // Get present CUDA and ROCM variants
    let cuda_variants_present_set = CUDA_COMPLIANT_VARIANTS
        .iter()
        .filter(|v| variants.iter().any(|variant| variant.to_string() == **v))
        .collect::<Vec<_>>();

    let rocm_variants_present_set = ROCM_COMPLIANT_VARIANTS
        .iter()
        .filter(|v| variants.iter().any(|variant| variant.to_string() == **v))
        .collect::<Vec<_>>();

    // Check if all required variants are present
    let cuda_compatible = cuda_variants_present_set.len() == CUDA_COMPLIANT_VARIANTS.len();
    let rocm_compatible = rocm_variants_present_set.len() == ROCM_COMPLIANT_VARIANTS.len();

    if format == Format::Json {
        // Create JSON response
        let json_output = serde_json::json!({
            "repository": repo_id,
            "status": "success",
            "build_status": {
                "summary": build_status,
                "cuda": {
                    "compatible": cuda_compatible,
                    "present": cuda_variants_present_set.iter().map(|&v| v.to_string()).collect::<Vec<_>>(),
                    "missing": CUDA_COMPLIANT_VARIANTS.iter()
                        .filter(|v| !cuda_variants_present_set.contains(v))
                        .map(|&v| v.to_string())
                        .collect::<Vec<_>>()
                },
                "rocm": {
                    "compatible": rocm_compatible,
                    "present": rocm_variants_present_set.iter().map(|&v| v.to_string()).collect::<Vec<_>>(),
                    "missing": ROCM_COMPLIANT_VARIANTS.iter()
                        .filter(|v| !rocm_variants_present_set.contains(v))
                        .map(|&v| v.to_string())
                        .collect::<Vec<_>>()
                }
            },
            "abi_status": {
                "compatible": abi_output.overall_compatible,
                "manylinux_version": abi_output.manylinux_version,
                "python_abi_version": abi_output.python_abi_version.to_string(),
                "variants": abi_output.variants.iter().map(|v| {
                    serde_json::json!({
                        "name": v.name,
                        "compatible": v.is_compatible,
                        "has_shared_objects": v.has_shared_objects,
                        "violations": v.violations.iter().map(|viol| viol.message.clone()).collect::<Vec<_>>()
                    })
                }).collect::<Vec<_>>()
            }
        });

        // Output pretty-printed JSON
        println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
    } else {
        let abi_mark = if abi_output.overall_compatible {
            "✓".green()
        } else {
            "✗".red()
        };

        let label = format!(" {} ", repo_id).black().on_bright_white().bold();

        println!("\n{}", label);
        println!("├── build: {}", build_status);

        let cuda_mark = if cuda_compatible {
            "✓".green()
        } else {
            "✗".red()
        };
        let rocm_mark = if rocm_compatible {
            "✓".green()
        } else {
            "✗".red()
        };

        if !compact_output {
            println!("│  {} {}", cuda_mark, "CUDA".bold());

            // conditionally print the last item with a diffent box character
            for (i, cuda_variant) in CUDA_COMPLIANT_VARIANTS.iter().enumerate() {
                if i == CUDA_COMPLIANT_VARIANTS.len() - 1 {
                    if cuda_variants_present_set.contains(&cuda_variant) {
                        println!("│    ╰── {}", cuda_variant);
                    } else {
                        println!("│    ╰── {}", cuda_variant.dimmed());
                    }
                } else if cuda_variants_present_set.contains(&cuda_variant) {
                    println!("│    ├── {}", cuda_variant);
                } else {
                    println!("│    ├── {}", cuda_variant.dimmed());
                }
            }

            println!("│  {} ROCM", rocm_mark);

            for (i, rocm_variant) in ROCM_COMPLIANT_VARIANTS.iter().enumerate() {
                if i == ROCM_COMPLIANT_VARIANTS.len() - 1 {
                    if rocm_variants_present_set.contains(&rocm_variant) {
                        println!("│    ╰── {}", rocm_variant);
                    } else {
                        println!("│    ╰── {}", rocm_variant.dimmed());
                    }
                } else if rocm_variants_present_set.contains(&rocm_variant) {
                    println!("│    ├── {}", rocm_variant);
                } else {
                    println!("│    ├── {}", rocm_variant.dimmed());
                }
            }
        } else {
            println!("│   ├── {} CUDA", cuda_mark);
            println!("│   ╰── {} ROCM", rocm_mark);
        }
        println!("╰── abi: {}", abi_status);
        println!("    ├── {} {}", abi_mark, abi_output.manylinux_version);
        println!(
            "    ╰── {} python {}",
            abi_mark, abi_output.python_abi_version
        );
    }

    Ok(())
}

fn get_build_status_summary(
    build_dir: &Path,
    variants: &[String],
    cuda_variants: &[&str],
    rocm_variants: &[&str],
) -> String {
    let built = variants
        .iter()
        .filter(|v| build_dir.join(v).exists())
        .count();
    let cuda_built = variants
        .iter()
        .filter(|v| cuda_variants.contains(&v.as_str()) && build_dir.join(v).exists())
        .count();
    let rocm_built = variants
        .iter()
        .filter(|v| rocm_variants.contains(&v.as_str()) && build_dir.join(v).exists())
        .count();
    format!(
        "Total: {} (CUDA: {}, ROCM: {})",
        built, cuda_built, rocm_built
    )
}

fn get_cache_dir() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let cache_dir = if let Ok(dir) = std::env::var("HF_KERNELS_CACHE") {
        PathBuf::from(dir)
    } else {
        dirs::home_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join(".cache/huggingface/hub")
    };
    if !cache_dir.exists() {
        fs::create_dir_all(&cache_dir)?;
    }
    Ok(cache_dir)
}

fn get_repo_path(repo_id: &str, base_dir: &Path) -> PathBuf {
    let repo = Repo::with_revision(repo_id.to_string(), RepoType::Model, "main".to_string());
    base_dir.join(repo.folder_name())
}

fn fetch_repository(
    repo_id: &str,
    cache_dir: &Path,
    revision: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("fetching: {} (revision: {})", repo_id, revision);

    // TODO: revisit with slower manual download
    let mut cmd = std::process::Command::new("huggingface-cli");
    cmd.arg("download")
        .arg(repo_id)
        .arg("--revision")
        .arg(revision)
        .arg("--cache-dir")
        .arg(cache_dir);

    let status = cmd.status()?;
    if !status.success() {
        return Err(Box::new(std::io::Error::new(
            std::io::ErrorKind::Other,
            "command failed",
        )));
    }

    Ok(())
}

fn get_build_variants(repo_path: &Path) -> Result<Vec<Variant>, Box<dyn std::error::Error>> {
    let build_dir = repo_path.join("build");
    let mut variants = Vec::new();
    if !build_dir.exists() {
        return Ok(variants);
    }
    let entries = fs::read_dir(build_dir)?;
    for entry in entries {
        let entry = entry?;
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

#[derive(Debug, Clone)]
pub struct SharedObjectViolation {
    pub message: String,
    // TODO: Explore what other fields we may need
}

#[derive(Debug, Clone)]
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

fn check_abi_for_repository(
    snapshot_dir: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    show_violations: bool,
) -> Result<AbiCheckResult, Box<dyn std::error::Error>> {
    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        return Ok(AbiCheckResult {
            overall_compatible: false,
            variants: Vec::new(),
            manylinux_version: manylinux_version.to_string(),
            python_abi_version: python_abi_version.clone(),
        });
    }

    // Get all variant directories
    let variant_paths: Vec<PathBuf> = fs::read_dir(&build_dir)?
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|path| path.is_dir())
        .collect();

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
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        let so_files = find_shared_objects(variant_path)?;
        let has_shared_objects = !so_files.is_empty();

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
            )?;

            if !passed && show_violations {
                // TODO: parse the violations_text more carefully
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

fn find_shared_objects(dir: &Path) -> Result<Vec<PathBuf>, Box<dyn std::error::Error>> {
    let mut so_files = Vec::new();
    if !dir.exists() || !dir.is_dir() {
        return Ok(so_files);
    }
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            let mut subdir_so_files = find_shared_objects(&path)?;
            so_files.append(&mut subdir_so_files);
        } else if let Some(extension) = path.extension() {
            if extension == "so" {
                so_files.push(path);
            }
        }
    }
    Ok(so_files)
}

fn check_shared_object(
    so_path: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    show_violations: bool,
) -> Result<(bool, String), Box<dyn std::error::Error>> {
    let mut violations_output = String::new();

    let binary_data = fs::read(so_path).map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("cannot read shared object file: {}", e),
        )
    })?;

    let file = object::File::parse(&*binary_data).map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("cannot parse object file: {}", e),
        )
    })?;

    let manylinux_result = check_manylinux(
        manylinux_version,
        file.architecture(),
        file.endianness(),
        file.symbols(),
    )
    .map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("manylinux check error: {}", e),
        )
    })?;

    let python_abi_result = check_python_abi(python_abi_version, file.symbols()).map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("python abi check error: {}", e),
        )
    })?;

    let passed = manylinux_result.is_empty() && python_abi_result.is_empty();

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
