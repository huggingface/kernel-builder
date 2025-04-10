use std::path::PathBuf;
use std::{collections::BTreeSet, fs};

use clap::Parser;
use eyre::{Context, Result};
use object::Object;

use kernel_abi_check::{
    check_manylinux, check_python_abi, ManylinuxViolation, PythonAbiViolation, Version,
};

/// CLI tool to check library versions
#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Python extension library.
    object: PathBuf,

    /// Manylinux version.
    #[arg(short, long, value_name = "VERSION", default_value = "manylinux_2_28")]
    manylinux: String,

    /// Python ABI version.
    #[arg(short, long, value_name = "VERSION", default_value = "3.9")]
    python_abi: Version,
}

fn main() -> Result<()> {
    // Initialize color_eyre error handling
    color_eyre::install()?;

    // Parse command-line arguments
    let args = Cli::parse();

    eprintln!(
        "🐍 Checking for compatibility with {} and Python ABI version {}",
        args.manylinux, args.python_abi
    );

    let binary_data = fs::read(args.object).context("Cannot open object file")?;
    let file = object::File::parse(&*binary_data).context("Cannot parse object")?;

    let many_linux_violations = check_manylinux(&args.manylinux, file.symbols())?;
    print_manylinux_violations(&many_linux_violations, &args.manylinux)?;

    let python_abi_violations = check_python_abi(&args.python_abi, file.symbols())?;
    print_python_abi_violations(&python_abi_violations, &args.python_abi);

    if !(many_linux_violations.is_empty() && python_abi_violations.is_empty()) {
        return Err(eyre::eyre!("Incompatible symbols found"));
    } else {
        eprintln!("✅ No compatibility issues found");
    }

    Ok(())
}

fn print_manylinux_violations(
    violations: &BTreeSet<ManylinuxViolation>,
    manylinux_version: &str,
) -> Result<()> {
    if !violations.is_empty() {
        eprintln!(
            "\n⛔ Symbols incompatible with `{}` found:\n",
            manylinux_version
        );
        for violation in violations {
            match violation {
                ManylinuxViolation::Symbol { name, dep, version } => {
                    eprintln!("{}_{}: {}", name, dep, version);
                }
            }
        }
    }
    Ok(())
}

fn print_python_abi_violations(violations: &BTreeSet<PythonAbiViolation>, python_abi: &Version) {
    if !violations.is_empty() {
        let newer_abi3_symbols = violations
            .iter()
            .filter(|v| matches!(v, PythonAbiViolation::IncompatibleAbi3Symbol { .. }))
            .collect::<BTreeSet<_>>();
        let non_abi3_symbols = violations
            .iter()
            .filter(|v| matches!(v, PythonAbiViolation::NonAbi3Symbol { .. }))
            .collect::<BTreeSet<_>>();

        if !newer_abi3_symbols.is_empty() {
            eprintln!("\n⛔ Symbols >= Python ABI {} found:\n", python_abi);
            for violation in newer_abi3_symbols {
                if let PythonAbiViolation::IncompatibleAbi3Symbol { name, added } = violation {
                    eprintln!("{}: {}", name, added);
                }
            }
        }

        if !non_abi3_symbols.is_empty() {
            eprintln!("\n⛔ Non-ABI3 symbols found:\n");
            for violation in &non_abi3_symbols {
                if let PythonAbiViolation::NonAbi3Symbol { name } = violation {
                    eprintln!("{}", name);
                }
            }
        }
    }
}
