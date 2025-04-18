use std::{collections::HashMap, fmt::Display, path::PathBuf};

use itertools::Itertools;
use serde::Deserialize;

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

impl Torch {
    pub fn data_globs(&self) -> Option<Vec<String>> {
        match self.pyext.as_ref() {
            Some(exts) => {
                let globs = exts
                    .iter()
                    .filter(|&ext| ext != "py" && ext != "pyi")
                    .map(|ext| format!("\"**/*.{}\"", ext))
                    .collect_vec();
                if globs.is_empty() {
                    None
                } else {
                    Some(globs)
                }
            }

            None => None,
        }
    }
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

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum Language {
    #[default]
    Cuda,
    CudaHipify,
}

impl Display for Language {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Language::Cuda => f.write_str("cuda"),
            Language::CudaHipify => f.write_str("cuda-hipify"),
        }
    }
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
    #[serde[rename = "cutlass_3_8"]]
    Cutlass3_8,
    Torch,
}
