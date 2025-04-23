use anyhow::{Context, Result};
use clap::Parser;
use kernel_abi_check::Version;
use std::str::FromStr;

fn main() -> Result<()> {
    // Parse CLI arguments
    let cli = compliant::Cli::parse();

    // Get cache directory
    let cache_dir = compliant::get_cache_dir().context("Failed to determine cache directory")?;

    match cli.command {
        compliant::Commands::List { format } => {
            // List repositories with build variants
            list_repositories(&cache_dir, format)?;
        }

        compliant::Commands::Check {
            repos,
            manylinux,
            python_abi,
            auto_fetch,
            revision,
            long,
            show_violations,
            format,
        } => {
            // Check repositories for compliance
            check_repositories(
                &repos,
                &cache_dir,
                &manylinux,
                &python_abi,
                auto_fetch,
                &revision,
                long,
                show_violations,
                format,
            )?;
        }
    }

    Ok(())
}

fn list_repositories(cache_dir: &std::path::Path, format: compliant::Format) -> Result<()> {
    let entries = std::fs::read_dir(cache_dir)
        .with_context(|| format!("Failed to read cache directory: {:?}", cache_dir))?;

    let mut found_repos = 0;
    let mut repo_list = Vec::new();

    for entry in entries {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();

        if !path.is_dir() {
            continue;
        }

        // Extract repo ID from path
        let repo_id = compliant::get_repo_id_from_path(&path)
            .with_context(|| format!("Failed to extract repo ID from path: {:?}", path))?;

        // Check if this repo has a build directory with variants
        if compliant::has_build_variants(&path)
            .with_context(|| format!("Failed to check for build variants in: {:?}", path))?
        {
            repo_list.push(repo_id);
            found_repos += 1;
        }
    }

    // Sort repositories for consistent display
    repo_list.sort();

    if format.is_json() {
        // Create JSON response
        let result = compliant::RepoListResult {
            repositories: repo_list,
            count: found_repos,
        };
        let json =
            serde_json::to_string_pretty(&result).context("Failed to serialize JSON response")?;
        println!("{}", json);
    } else {
        compliant::ConsoleFormatter::format_repo_list(&repo_list, found_repos);
    }

    Ok(())
}

fn check_repositories(
    repos: &str,
    cache_dir: &std::path::Path,
    manylinux: &str,
    python_abi: &str,
    auto_fetch: bool,
    revision: &str,
    long: bool,
    show_violations: bool,
    format: compliant::Format,
) -> Result<()> {
    let repositories: Vec<String> = repos
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    if repositories.is_empty() {
        #[derive(serde::Serialize)]
        struct ErrorResponse {
            status: &'static str,
            error: &'static str,
        }

        if format.is_json() {
            let error = ErrorResponse {
                status: "error",
                error: "no repository ids provided",
            };
            let json = serde_json::to_string_pretty(&error)
                .context("Failed to serialize error response")?;
            println!("{}", json);
        } else {
            eprintln!("no repository ids provided");
        }
        return Ok(());
    }

    let python_version = Version::from_str(python_abi)
        .map_err(|e| anyhow::anyhow!("Invalid Python ABI version {}: {}", python_abi, e))?;

    for repo_id in &repositories {
        if let Err(e) = compliant::process_repository(
            repo_id,
            cache_dir,
            revision,
            auto_fetch,
            manylinux,
            &python_version,
            !long,
            show_violations,
            format,
        ) {
            eprintln!("Error processing repository {}: {}", repo_id, e);

            // Continue processing other repositories rather than exiting early
            // This is more user-friendly for batch processing
        }
    }

    Ok(())
}
