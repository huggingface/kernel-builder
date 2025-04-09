use std::collections::{BTreeSet, HashSet};
use std::env::consts;
use std::str;
use std::{collections::HashMap, str::FromStr};

use eyre::{Context, ContextCompat, OptionExt, Result};
use object::{ObjectSymbol, Symbol};
use once_cell::sync::Lazy;
use serde::Deserialize;

use crate::Version;

#[derive(Debug, Deserialize)]
struct ManyLinux {
    name: String,
    #[allow(dead_code)]
    aliases: Vec<String>,
    #[allow(dead_code)]
    priority: u32,
    symbol_versions: HashMap<String, HashMap<String, HashSet<String>>>,
    #[allow(dead_code)]
    lib_whitelist: Vec<String>,
    #[allow(dead_code)]
    blacklist: HashMap<String, Vec<String>>,
}

static MANYLINUX_POLICY_JSON: &str = include_str!("manylinux-policy.json");

static MANYLINUX_VERSIONS: Lazy<HashMap<String, ManyLinux>> = Lazy::new(|| {
    let deserialized: Vec<ManyLinux> = serde_json::from_str(MANYLINUX_POLICY_JSON).unwrap();
    deserialized
        .into_iter()
        .map(|manylinux| (manylinux.name.clone(), manylinux))
        .collect()
});

/// A violation of the manylinux policy.
#[derive(Debug, Clone, Eq, Ord, PartialEq, PartialOrd)]
pub enum ManylinuxViolation {
    /// A symbol is not allowed in the manylinux version.
    Symbol {
        name: String,
        dep: String,
        version: String,
    },
}

pub fn check_manylinux<'a>(
    manylinux_version: &str,
    symbols: impl IntoIterator<Item = Symbol<'a, 'a>>,
) -> Result<BTreeSet<ManylinuxViolation>> {
    let symbol_versions = MANYLINUX_VERSIONS
        .get(manylinux_version)
        .context(format!("Unknown manylinux version: {}", manylinux_version))?
        .symbol_versions
        .get(consts::ARCH)
        .context(format!(
            "Cannot find arch `{}` for: {}`",
            consts::ARCH,
            manylinux_version
        ))?;

    let mut violations = BTreeSet::new();

    for symbol in symbols {
        if symbol.is_undefined() {
            let symbol = symbol.name_bytes().context("Cannot get symbol name")?;
            let symbol = str::from_utf8(symbol).context("Cannot parse symbol name as UTF-8")?;

            let mut symbol_parts = symbol.split('@');
            let symbol_name = symbol_parts.next().context("Cannot get symbol name")?;

            let version_info = match symbol_parts.next() {
                Some(version_info) => version_info,
                None => continue,
            };

            let mut version_parts = version_info.split('_');

            let dep = version_parts
                .next()
                .ok_or_eyre("Cannot get symbol version name")?;

            let version = match version_parts.next() {
                Some(version) => Version::from_str(version)?,
                // We also get symbol versions like: libcudart.so.12
                None => continue,
            };

            if let Some(versions) = symbol_versions.get(dep) {
                if !versions.contains(&version.to_string()) {
                    violations.insert(ManylinuxViolation::Symbol {
                        name: symbol_name.to_string(),
                        dep: dep.to_string(),
                        version: version.to_string(),
                    });
                }
            }
        }
    }

    Ok(violations)
}
