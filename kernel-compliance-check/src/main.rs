use core::str::FromStr as _;

use clap::Parser as _;
use eyre::{Context as _, Result};
use kernel_abi_check::Version;
use kernel_compliance_check::{process_repository, Cli, Commands, Format};

fn main() -> Result<()> {
    // Parse CLI arguments
    let cli = Cli::parse();

    // Respect KERNELS_CACHE if set
    let non_standard_cache: Option<String> = std::env::var("KERNELS_CACHE").ok();

    // Prefer the cli unless explicitly set to avoid it
    let prefer_hub_cli = !std::env::var("AVOID_HUB_CLI")
        .map(|v| v == "1" || v == "true")
        .unwrap_or(false);

    match cli.command {
        Commands::Check {
            repos,
            manylinux,
            python_abi,
            revision,
            long,
            force_fetch,
            show_violations,
            format,
        } => {
            eprintln!("Running kernel compliance check");
            eprintln!("Repositories: {repos}");
            eprintln!("Kernel Revision: {revision}");

            // Check repositories for compliance
            check_repositories(
                &repos,
                &manylinux.to_string(),
                &python_abi,
                prefer_hub_cli,
                force_fetch,
                &revision,
                long,
                show_violations,
                format,
                non_standard_cache.as_ref(),
            )?;
        }
    }

    Ok(())
}

#[allow(clippy::fn_params_excessive_bools)]
#[expect(clippy::too_many_arguments)]
fn check_repositories(
    repos: &str,
    manylinux: &str,
    python_abi: &str,
    prefer_hub_cli: bool,
    force_fetch: bool,
    revision: &str,
    long: bool,
    show_violations: bool,
    format: Format,
    non_standard_cache: Option<&String>,
) -> Result<()> {
    let repositories: Vec<String> = repos
        .split(',')
        .map(|s| s.trim().to_owned())
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
            println!("{json}");
        } else {
            eprintln!("no repository ids provided");
        }
        return Ok(());
    }

    let python_version = Version::from_str(python_abi)
        .map_err(|e| eyre::eyre!("Invalid Python ABI version {}: {}", python_abi, e))?;

    for repo_id in &repositories {
        if let Err(e) = process_repository(
            repo_id,
            revision,
            force_fetch,
            prefer_hub_cli,
            manylinux,
            &python_version,
            !long,
            show_violations,
            format,
            non_standard_cache,
        ) {
            eprintln!("Error processing repository {repo_id}: {e}");

            // Continue processing other repositories rather than exiting early
            // This is more user-friendly for batch processing
        }
    }

    Ok(())
}
