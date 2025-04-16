use clap::Parser;
use kernel_abi_check::Version;
use std::str::FromStr;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = compliant::Cli::parse();
    let cache_dir = compliant::get_cache_dir()?;

    match cli.command {
        compliant::Commands::List { format } => {
            let entries = std::fs::read_dir(&cache_dir)?;
            let mut found_repos = 0;
            let mut repo_list = Vec::new();

            for entry in entries {
                let entry = entry?;
                let path = entry.path();

                if !path.is_dir() {
                    continue;
                }

                // Extract repo ID from path
                let repo_id = compliant::get_repo_id_from_path(&path)?;

                // Check if this repo has a build directory with variants
                if compliant::has_build_variants(&path)? {
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
                println!("{}", serde_json::to_string_pretty(&result).unwrap());
            } else {
                compliant::ConsoleFormatter::format_repo_list(&repo_list, found_repos);
            }
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
                    println!("{}", serde_json::to_string_pretty(&error).unwrap());
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
                compliant::process_repository(
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
