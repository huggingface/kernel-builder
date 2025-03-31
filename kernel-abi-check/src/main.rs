use std::collections::HashMap;
use std::fmt::Display;
use std::fs;
use std::path::PathBuf;
use std::str;

use clap::Parser;
use eyre::{ensure, Context, ContextCompat, OptionExt, Result};
use object::{Object, ObjectSymbol};

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Version(Vec<usize>);

impl Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}",
            itertools::join(self.0.iter().map(|v| v.to_string()), ".")
        )
    }
}

fn abi_versions(system: &str) -> Result<(Version, Version)> {
    match system {
        "ubuntu-20.04" => Ok((Version(vec![2, 31]), Version(vec![3, 4, 28]))),
        system => Err(eyre::eyre!("System ABI unknown: {}", system)),
    }
}

/// CLI tool to check library versions
#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    system: String,
    object: PathBuf,
}

/// Validate version string format
fn parse_version(version: &str) -> Result<Version> {
    let version = version.trim().to_owned();
    ensure!(!version.is_empty(), "Empty version string");
    let mut version_parts = Vec::new();
    for part in version.split('.') {
        let version_part: usize = part.parse().context("Version must consist of numbers")?;
        version_parts.push(version_part);
    }

    Ok(Version(version_parts))
}

fn main() -> Result<()> {
    // Initialize color_eyre error handling
    color_eyre::install()?;

    // Parse command-line arguments
    let args = Cli::parse();

    let binary_data = fs::read(args.object).context("Cannot open object file")?;
    let file = object::File::parse(&*binary_data).context("Cannot parse object")?;

    let (max_glibc_version, max_libstdcxx_version) = abi_versions(&args.system)?;

    let mut versions = HashMap::new();

    for symbol in file.symbols() {
        if symbol.is_undefined() {
            let symbol = symbol.name_bytes().context("Cannot get symbol name")?;
            let symbol = str::from_utf8(symbol).context("Cannot parse symbol name as UTF-8")?;

            let mut symbol_parts = symbol.split('@');
            symbol_parts.next().context("Cannot get symbol name")?;

            let version_info = match symbol_parts.next() {
                Some(version_info) => version_info,
                None => continue,
            };

            let mut version_parts = version_info.split('_');

            let dep = version_parts
                .next()
                .ok_or_eyre("Cannot get symbol version name")?;

            let version = match version_parts.next() {
                Some(version) => parse_version(version)?,
                // We also get symbol versions like: libcudart.so.12
                None => continue,
            };

            versions
                .entry(dep.to_owned())
                .and_modify(|v| {
                    if &version > v {
                        *v = version.clone();
                    }
                })
                .or_insert(version);
        }
    }

    let mut error = false;

    if let Some(glibc_version) = versions.get("GLIBC") {
        let status = if glibc_version > &max_glibc_version {
            error = true;
            "⛔"
        } else {
            "✅"
        };
        eprintln!(
            "{} glibc symbol version max: {}, found: {}",
            status, max_glibc_version, glibc_version,
        );
    }

    if let Some(libcxx_version) = versions.get("GLIBCXX") {
        let status = if libcxx_version > &max_libstdcxx_version {
            error = true;
            "⛔"
        } else {
            "✅"
        };
        eprintln!(
            "{} libstdc++ symbol version max: {}, found: {}",
            status, max_libstdcxx_version, libcxx_version
        );
    } else {
        eprintln!(
            "✅ libstdc++ symbol version max: {}, found: none",
            max_libstdcxx_version
        );
    }

    if error {
        return Err(eyre::eyre!("Incompatible symbols found"));
    }

    Ok(())
}
