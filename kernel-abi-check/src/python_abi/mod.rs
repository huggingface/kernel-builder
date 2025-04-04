use std::collections::{BTreeMap, BTreeSet, HashMap};

use eyre::Result;
use object::{ObjectSymbol, Symbol};
use once_cell::sync::Lazy;
use serde::Deserialize;

use crate::version::Version;

static ABI_TOML: &str = include_str!("stable_abi.toml");

#[derive(Deserialize)]
struct AbiInfoSerde {
    added: Version,
}

#[derive(Deserialize)]
struct StableAbiSerde {
    function: HashMap<String, AbiInfoSerde>,
    data: HashMap<String, AbiInfoSerde>,
}

#[derive(Clone, Copy, Debug)]
pub enum SymbolType {
    Data,
    Function,
}

#[derive(Clone, Debug)]
pub struct AbiInfo {
    #[allow(dead_code)]
    pub symbol_type: SymbolType,
    pub added: Version,
}

pub static PYTHON_STABLE_ABI: Lazy<HashMap<String, AbiInfo>> = Lazy::new(|| {
    let deserialized: StableAbiSerde = toml::de::from_str(ABI_TOML).unwrap();
    let mut symbols = HashMap::new();
    for (name, abi) in deserialized.function {
        symbols.insert(
            name,
            AbiInfo {
                symbol_type: SymbolType::Function,
                added: abi.added,
            },
        );
    }
    for (name, abi) in deserialized.data {
        symbols.insert(
            name,
            AbiInfo {
                symbol_type: SymbolType::Data,
                added: abi.added,
            },
        );
    }
    symbols
});

pub fn check_python_abi<'a>(
    python_abi: &Version,
    symbols: impl IntoIterator<Item = Symbol<'a, 'a>>,
) -> Result<bool> {
    let mut newer_abi3_symbols = BTreeMap::new();
    let mut non_abi3_symbols = BTreeSet::new();

    for symbol in symbols {
        if !symbol.is_undefined() {
            continue;
        }

        let symbol_name = symbol.name()?;

        match PYTHON_STABLE_ABI.get(symbol_name) {
            Some(abi_info) => {
                if &abi_info.added > python_abi {
                    newer_abi3_symbols.insert(symbol_name, abi_info);
                }
            }
            None => {
                if symbol_name.starts_with("Py") || symbol_name.starts_with("_Py") {
                    non_abi3_symbols.insert(symbol_name);
                }
            }
        }
    }

    if !newer_abi3_symbols.is_empty() {
        eprintln!("\n⛔ Symbols >= Python ABI {} found:\n", python_abi);
        for (name, abi_info) in &newer_abi3_symbols {
            eprintln!("{}: {}", name, abi_info.added);
        }
    }

    if !non_abi3_symbols.is_empty() {
        eprintln!("\n⛔ Non-ABI3 symbols found:\n");
        for name in &non_abi3_symbols {
            eprintln!("{}", name);
        }
    }

    Ok(!newer_abi3_symbols.is_empty() || !non_abi3_symbols.is_empty())
}
