use std::{collections::HashMap, path::PathBuf};

use itertools::Itertools;
use serde::{Deserialize, Serialize};

use super::v1;

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub general: General,
    pub torch: Option<Torch>,

    #[serde(rename = "kernel", default)]
    pub kernels: HashMap<String, Kernel>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct General {
    pub name: String,
    #[serde(default)]
    pub compute_framework: ComputeFramework,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum ComputeFramework {
    #[default]
    Cuda,
    Universal,
}

#[derive(Debug, Deserialize, Clone, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Torch {
    pub include: Option<Vec<String>>,
    pub pyext: Option<Vec<String>>,

    #[serde(default)]
    pub src: Vec<PathBuf>,
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

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct Kernel {
    #[serde(default)]
    pub supports_hipify: bool,
    pub cuda_capabilities: Option<Vec<String>>,
    pub rocm_archs: Option<Vec<String>>,
    pub depends: Vec<Dependencies>,
    pub include: Option<Vec<String>>,
    pub src: Vec<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
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

impl From<v1::Build> for Build {
    fn from(build: v1::Build) -> Self {
        let universal = build
            .torch
            .as_ref()
            .map(|torch| torch.universal)
            .unwrap_or(false);
        Self {
            general: General::from(build.general, universal),
            torch: build.torch.map(Into::into),
            kernels: build
                .kernels
                .into_iter()
                .map(|(k, v)| (k, v.into()))
                .collect(),
        }
    }
}

impl General {
    fn from(general: v1::General, universal: bool) -> Self {
        Self {
            name: general.name,
            // v1 only supported CUDA and universal.
            compute_framework: if universal {
                ComputeFramework::Universal
            } else {
                ComputeFramework::Cuda
            },
        }
    }
}

impl From<v1::Kernel> for Kernel {
    fn from(kernel: v1::Kernel) -> Self {
        Self {
            supports_hipify: kernel.language == v1::Language::CudaHipify,
            cuda_capabilities: kernel.cuda_capabilities,
            rocm_archs: kernel.rocm_archs,
            depends: kernel.depends,
            include: kernel.include,
            src: kernel.src,
        }
    }
}

impl From<v1::Torch> for Torch {
    fn from(torch: v1::Torch) -> Self {
        Self {
            include: torch.include,
            pyext: torch.pyext,
            src: torch.src,
        }
    }
}
