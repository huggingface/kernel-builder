use std::fs;
use std::path::PathBuf;

use clap::Parser;
use eyre::{Context, Result};
use object::Object;

mod manylinux;
pub use manylinux::check_manylinux_symbols;

mod python_abi;
pub use python_abi::check_python_abi;

mod version;
pub use version::Version;

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

    let mut error = false;
    error |= check_manylinux_symbols(&args.manylinux, file.symbols())?;
    error |= check_python_abi(&args.python_abi, file.symbols())?;

    if error {
        return Err(eyre::eyre!("Incompatible symbols found"));
    } else {
        eprintln!("✅ No compatibility issues found");
    }

    Ok(())
}
