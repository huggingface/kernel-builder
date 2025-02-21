use std::{collections::HashMap, path::PathBuf};

use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub general: General,
    pub torch: Option<Torch>,

    #[serde(rename = "kernel")]
    pub kernels: HashMap<String, Kernel>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct General {
    pub name: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Torch {
    pub include: Option<Vec<String>>,
    pub pyext: Option<Vec<String>>,
    pub src: Vec<PathBuf>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct Kernel {
    pub cuda_capabilities: Vec<String>,
    pub depends: Vec<Dependencies>,
    pub include: Option<Vec<String>>,
    pub src: Vec<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq)]
#[non_exhaustive]
#[serde(rename_all = "lowercase")]
pub enum Dependencies {
    #[serde[rename = "cutlass_2_10"]]
    Cutlass2_10,
    #[serde[rename = "cutlass_3_5"]]
    Cutlass3_5,
    #[serde[rename = "cutlass_3_6"]]
    Cutlass3_6,
    Torch,
}
