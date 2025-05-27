use serde::Deserialize;

pub mod v1;

mod v2;
pub use v2::{Build, ComputeFramework, Dependencies, Kernel, Torch};

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum BuildCompat {
    V1(v1::Build),
    V2(Build),
}

impl From<BuildCompat> for Build {
    fn from(compat: BuildCompat) -> Self {
        match compat {
            BuildCompat::V1(v1_build) => v1_build.into(),
            BuildCompat::V2(v2_build) => v2_build,
        }
    }
}
