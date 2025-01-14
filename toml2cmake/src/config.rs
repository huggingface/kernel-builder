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
    pub version: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Torch {
    pub name: String,
    pub include: Option<Vec<String>>,
    // Used by the builder, so we have to accept this field.
    #[serde(rename = "pyext")]
    pub _pyext: Option<Vec<String>>,
    pub pyroot: PathBuf,
    pub src: Vec<PathBuf>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Kernel {
    pub capabilities: Vec<String>,
    pub depends: Vec<Dependencies>,
    pub include: Option<Vec<String>>,
    pub src: Vec<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq)]
#[non_exhaustive]
#[serde(rename_all = "lowercase")]
pub enum Dependencies {
    Cutlass,
    Torch,
}
