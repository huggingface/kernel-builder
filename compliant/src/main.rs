use clap::{Parser, Subcommand};
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

#[derive(Subcommand)]
enum Commands {
    /// List fetched repositories with build variants
    List,

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

        /// Skip ABI compatibility check
        #[arg(long)]
        skip_abi: bool,

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

const ROCM_COMPLIANT_VARIANTS: [&str; 6] = [
    "torch25-cxx11-rocm5.4-x86_64-linux",
    "torch25-cxx11-rocm5.6-x86_64-linux",
    "torch25-cxx98-rocm5.4-x86_64-linux",
    "torch25-cxx98-rocm5.6-x86_64-linux",
    "torch26-cxx11-rocm5.4-x86_64-linux",
    "torch26-cxx11-rocm5.6-x86_64-linux",
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
        Commands::List => {
            let entries = fs::read_dir(&cache_dir)?;
            let mut found_repos = 0;

            println!("repositories with build variants");
            println!("-------------------------------");

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
                    println!("{}", repo_id);
                    found_repos += 1;
                }
            }

            if found_repos == 0 {
                println!("no repositories with build variants found");
            } else {
                println!("\ntotal: {} repositories", found_repos);
            }
        }

        Commands::Check {
            repos,
            manylinux,
            python_abi,
            skip_abi,
            auto_fetch,
            revision,
            long,
            show_violations,
        } => {
            let repositories: Vec<String> = repos
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();

            if repositories.is_empty() {
                eprintln!("no repository ids provided");
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
                    skip_abi,
                    !long,
                    show_violations,
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
    skip_abi: bool,
    compact_output: bool,
    show_violations: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let repo_path = get_repo_path(repo_id, cache_dir);

    // Check if repository exists locally
    if !repo_path.exists() || !repo_path.join("refs/main").exists() {
        if auto_fetch {
            println!("repository: {}", repo_id);
            println!("status: not found locally, fetching...");

            // Fetch the repository
            match fetch_repository(repo_id, cache_dir, revision) {
                Ok(_) => println!("status: fetch successful"),
                Err(e) => {
                    println!("status: fetch failed - {}", e);
                    println!("---");
                    return Ok(());
                }
            }
        } else {
            print_repo_status(repo_id, "missing", "n/a", "n/a", "n/a");
            return Ok(());
        }
    }

    // Re-check after potential fetch
    let ref_file = repo_path.join("refs/main");
    if !ref_file.exists() {
        print_repo_status(repo_id, "missing", "n/a", "n/a", "n/a");
        return Ok(());
    }

    let content = fs::read_to_string(ref_file)?;
    let hash = content.trim();
    let snapshot_dir = repo_path.join(format!("snapshots/{}", hash));

    if !snapshot_dir.exists() {
        print_repo_status(repo_id, "present", "missing", "n/a", "n/a");
        return Ok(());
    }

    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        print_repo_status(repo_id, "present", "present", "missing", "n/a");
        return Ok(());
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

    let abi_status;
    let abi_details;

    if skip_abi {
        abi_status = "skipped";
        abi_details = String::new();
    } else {
        let (is_compatible, details) = check_abi_for_repository(
            &snapshot_dir,
            manylinux,
            python_version,
            compact_output,
            show_violations,
        )?;

        abi_status = if is_compatible {
            "compatible"
        } else {
            "incompatible"
        };
        abi_details = details;
    }

    print_repo_status(repo_id, "present", "present", &build_status, abi_status);

    // Print ABI check details after the status box
    if !abi_details.is_empty() {
        println!("{}", abi_details);
    }

    Ok(())
}

fn print_repo_status(
    repo_id: &str,
    refs_status: &str,
    snapshot_status: &str,
    build_status: &str,
    abi_status: &str,
) {
    // Create a divider line that matches the content width
    let divider = |ch: char, corner_left: char, corner_right: char, width: usize| {
        format!(
            "{}{}{}",
            corner_left,
            ch.to_string().repeat(width - 2),
            corner_right
        )
    };

    // Calculate the width of our table
    let max_width = 60;

    // Create top, middle and bottom borders with single line characters
    let top_border = divider('─', '┌', '┐', max_width);
    let mid_border = divider('─', '├', '┤', max_width);
    let bottom_border = divider('─', '└', '┘', max_width);

    // Print formatted box table
    println!("{}", top_border);
    println!("│ {:<56} │", format!("Repository: {}", repo_id));
    println!("{}", mid_border);
    println!(
        "│ {:<56} │",
        format!("Status: refs={}, snapshot={}", refs_status, snapshot_status)
    );
    println!("│ {:<56} │", format!("Build: {}", build_status));
    println!("│ {:<56} │", format!("ABI: {}", abi_status));
    println!("{}", bottom_border);
}

fn get_build_status_summary(
    build_dir: &Path,
    variants: &[String],
    cuda_variants: &[&str],
    rocm_variants: &[&str],
) -> String {
    let total = variants.len();
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
        "{}/{} (cuda:{}, rocm:{})",
        built, total, cuda_built, rocm_built
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

fn check_abi_for_repository(
    snapshot_dir: &Path,
    manylinux_version: &str,
    python_abi_version: &Version,
    compact_output: bool,
    show_violations: bool,
) -> Result<(bool, String), Box<dyn std::error::Error>> {
    let mut output = String::new();
    let build_dir = snapshot_dir.join("build");
    if !build_dir.exists() {
        return Ok((false, output));
    }

    // Get all variant directories
    let variant_paths: Vec<PathBuf> = fs::read_dir(&build_dir)?
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|path| path.is_dir())
        .collect();

    if variant_paths.is_empty() {
        return Ok((false, output));
    }

    let mut has_issues = false;
    let mut variant_results = Vec::new();

    // Skip detailed output in compact mode
    if !compact_output {
        output.push_str(&format!(
            "\nABI CHECK ( manylinux={}, python={} )\n\n",
            manylinux_version, python_abi_version
        ));
        output.push_str(&format!("{:<40} | {:<15}\n", "VARIANT", "STATUS"));
        output.push_str(&format!("{}\n", "-".repeat(48)));
    }

    // Check each variant
    for variant_path in &variant_paths {
        let variant_name = variant_path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();

        let so_files = find_shared_objects(variant_path)?;
        if so_files.is_empty() {
            if !compact_output {
                output.push_str(&format!("{:<40} | no shared objects\n", variant_name));
            }
            continue;
        }

        let mut variant_has_issues = false;
        let mut violations_output = String::new();

        // Check each shared object in the variant
        for so_path in &so_files {
            let (passed, violations) = check_shared_object(
                so_path,
                manylinux_version,
                python_abi_version,
                show_violations,
            )?;

            if !passed {
                variant_has_issues = true;
                has_issues = true;

                if show_violations {
                    violations_output.push_str(&violations);
                }
            }
        }

        if !compact_output {
            output.push_str(&format!(
                "{:<40} | {:<15}\n",
                variant_name,
                if variant_has_issues {
                    "incompatible"
                } else {
                    "compatible"
                }
            ));

            if show_violations && !violations_output.is_empty() {
                output.push_str(&violations_output);
            }
        }

        variant_results.push((variant_name.to_string(), !variant_has_issues));
    }

    // Only print summary statistics in compact mode
    if compact_output {
        let compatible_count = variant_results
            .iter()
            .filter(|(_, is_compatible)| *is_compatible)
            .count();
        let total_count = variant_results.len();
        output.push_str(&format!(
            "abi compatibility: {}/{} variants compatible\n",
            compatible_count, total_count
        ));
    }

    Ok((!has_issues, output))
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

    let manylinux_result = check_manylinux(manylinux_version, file.symbols()).map_err(|e| {
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
