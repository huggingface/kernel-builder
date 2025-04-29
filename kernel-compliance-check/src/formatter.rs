use crate::models::AbiCheckResult;
use colored::Colorize;

/// Struct for console output formatting
pub struct Console;

impl Console {
    pub fn format_repo_list(repos: &[String], count: usize) {
        println!(".");
        for repo_id in repos {
            println!("├── {repo_id}");
        }
        println!("╰── {count} kernel repositories found\n");
    }

    pub fn format_fetch_status(repo_id: &str, fetching: bool, result: Option<&str>) {
        println!("repository: {repo_id}");
        if fetching {
            println!("status: not found locally, fetching...");
        }
        if let Some(message) = result {
            println!("status: {message}");
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
        cuda_variants_present: &[String],
        #[cfg(feature = "enable_rocm")] rocm_variants_present: Vec<String>,
        #[cfg(not(feature = "enable_rocm"))] _rocm_variants_present: Vec<String>,
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

        let label = format!(" {repo_id} ").black().on_bright_white().bold();

        println!("\n{label}");
        println!("├── build: {build_status}");

        if compact_output {
            // Compact output
            #[cfg(feature = "enable_rocm")]
            {
                println!("│   ├── {} CUDA", cuda_mark);
                println!("│   ╰── {} ROCM", rocm_mark);
            }

            #[cfg(not(feature = "enable_rocm"))]
            {
                println!("│   ╰── {cuda_mark} CUDA");
            }
        } else {
            println!("│  {} {}", cuda_mark, "CUDA".bold());

            // Print variant list with proper tree characters
            let mut cuda_iter = cuda_variants.iter().peekable();
            while let Some(cuda_variant) = cuda_iter.next() {
                let is_last = cuda_iter.peek().is_none();
                let is_present = cuda_variants_present.contains(cuda_variant);
                let prefix = if is_last {
                    "│    ╰── "
                } else {
                    "│    ├── "
                };

                if is_present {
                    println!("{prefix}{cuda_variant}");
                } else {
                    println!("{}{}", prefix, cuda_variant.dimmed());
                }
            }

            // Only show ROCm section if the feature is enabled
            #[cfg(feature = "enable_rocm")]
            {
                println!("│  {} {}", rocm_mark, "ROCM".bold());

                let mut rocm_iter = rocm_variants.iter().peekable();
                while let Some(rocm_variant) = rocm_iter.next() {
                    let is_last = rocm_iter.peek().is_none();
                    let is_present = rocm_variants_present.contains(rocm_variant);
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
        }

        // ABI status section
        println!("╰── abi: {abi_status}");
        println!("    ├── {} {}", abi_mark, abi_output.manylinux_version);
        println!(
            "    ╰── {} python {}",
            abi_mark, abi_output.python_abi_version
        );
    }
}
