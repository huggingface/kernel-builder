use std::{fmt::Display, str::FromStr};

use eyre::{ensure, Context, Result};
use serde::{de, Deserialize, Deserializer};

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version(pub Vec<usize>);

impl<'de> Deserialize<'de> for Version {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        FromStr::from_str(&s).map_err(de::Error::custom)
    }
}

impl Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}",
            itertools::join(self.0.iter().map(|v| v.to_string()), ".")
        )
    }
}

impl FromStr for Version {
    type Err = eyre::Report;

    fn from_str(version: &str) -> Result<Self, Self::Err> {
        let version = version.trim().to_owned();
        ensure!(!version.is_empty(), "Empty version string");
        let mut version_parts = Vec::new();
        for part in version.split('.') {
            let version_part: usize = part.parse().context("Version must consist of numbers")?;
            version_parts.push(version_part);
        }

        Ok(Version(version_parts))
    }
}
