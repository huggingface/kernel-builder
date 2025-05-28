use eyre::Result;
use serde::Deserialize;

pub mod v1;

mod v2;
use serde_value::Value;
pub use v2::{Backend, Build, Dependencies, Kernel, Torch};

#[derive(Debug)]
pub enum BuildCompat {
    V1(v1::Build),
    V2(Build),
}

impl<'de> Deserialize<'de> for BuildCompat {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;

        match v1::Build::deserialize(value.clone()) {
            Ok(v1_build) => Ok(BuildCompat::V1(v1_build)),
            Err(_) => {
                let v2_build: Build =
                    Build::deserialize(value).map_err(serde::de::Error::custom)?;
                Ok(BuildCompat::V2(v2_build))
            }
        }
    }
}

impl TryFrom<BuildCompat> for Build {
    type Error = eyre::Error;

    fn try_from(compat: BuildCompat) -> Result<Self> {
        match compat {
            BuildCompat::V1(v1_build) => v1_build.try_into(),
            BuildCompat::V2(v2_build) => Ok(v2_build),
        }
    }
}
