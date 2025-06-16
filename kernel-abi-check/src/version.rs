use std::{fmt::Display, str::FromStr};

use eyre::{ensure, eyre, Context, Result};
use serde::{de, Deserialize, Deserializer};

/// Symbol version.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub major: usize,
    pub minor: usize,
    pub patch: usize,
}

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
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

impl FromStr for Version {
    type Err = eyre::Report;

    fn from_str(version: &str) -> Result<Self, Self::Err> {
        let version = version.trim().to_owned();
        ensure!(!version.is_empty(), "Empty version string");
        let mut parts_iter = version.split('.');
        let major = parts_iter
            .next()
            .ok_or_else(|| eyre!("Version does not contain major component: {}", version))?
            .parse()
            .context("Version must consist of numbers")?;
        let minor = parts_iter
            .next()
            .map(|s| s.parse())
            .unwrap_or(Ok(0))
            .context(format!("Cannot parse minor version in: {}", version))?;
        let patch = parts_iter
            .next()
            .map(|s| s.parse())
            .unwrap_or(Ok(0))
            .context(format!("Cannot parse patch version in: {}", version))?;

        ensure!(
            parts_iter.next().is_none(),
            "Version contains more than three components: {}",
            version
        );

        Ok(Version {
            major,
            minor,
            patch,
        })
    }
}
