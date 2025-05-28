use std::{collections::HashMap, fmt::Display, path::PathBuf};

use serde::Deserialize;

use super::v2::Dependencies;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub general: General,
    pub torch: Option<Torch>,

    #[serde(rename = "kernel", default)]
    pub kernels: HashMap<String, Kernel>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct General {
    pub name: String,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
pub struct Torch {
    pub include: Option<Vec<String>>,
    pub pyext: Option<Vec<String>>,

    #[serde(default)]
    pub src: Vec<PathBuf>,

    #[serde(default)]
    pub universal: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct Kernel {
    pub cuda_capabilities: Option<Vec<String>>,
    pub rocm_archs: Option<Vec<String>>,
    #[serde(default)]
    pub language: Language,
    pub depends: Vec<Dependencies>,
    pub include: Option<Vec<String>>,
    pub src: Vec<String>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum Language {
    #[default]
    Cuda,
    CudaHipify,
    Metal,
}

impl Display for Language {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Language::Cuda => f.write_str("cuda"),
            Language::CudaHipify => f.write_str("cuda-hipify"),
            Language::Metal => f.write_str("metal"),
        }
    }
}
