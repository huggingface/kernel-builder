use eyre::Result;
use serde::Deserialize;

pub mod v1;

mod v2;
pub use v2::{Backend, Build, Dependencies, Kernel, Torch};

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum BuildCompat {
    V1(v1::Build),
    V2(Build),
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
