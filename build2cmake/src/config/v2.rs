use std::{
    collections::{BTreeSet, HashMap},
    fmt::Display,
    path::PathBuf,
    str::FromStr,
};

use eyre::{bail, Result};
use itertools::Itertools;
use serde::{Deserialize, Serialize};

use super::v1::{self, Language};

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub general: General,
    pub torch: Option<Torch>,

    #[serde(rename = "kernel", default)]
    pub kernels: HashMap<String, Kernel>,
}

impl Build {
    pub fn has_kernel_with_backend(&self, backend: &Backend) -> bool {
        self.kernels
            .values()
            .any(|kernel| kernel.backend == *backend)
    }

    pub fn backends(&self) -> BTreeSet<Backend> {
        self.kernels.values().map(|kernel| kernel.backend).collect()
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct General {
    pub name: String,
    #[serde(default)]
    pub universal: bool,
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
    pub backend: Backend,
    pub cuda_capabilities: Option<Vec<String>>,
    pub rocm_archs: Option<Vec<String>>,
    pub depends: Vec<Dependencies>,
    pub include: Option<Vec<String>>,
    pub src: Vec<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum Backend {
    Cuda,
    Metal,
    Rocm,
}

impl Display for Backend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Backend::Cuda => write!(f, "cuda"),
            Backend::Metal => write!(f, "metal"),
            Backend::Rocm => write!(f, "rocm"),
        }
    }
}

impl FromStr for Backend {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "cuda" => Ok(Backend::Cuda),
            "metal" => Ok(Backend::Metal),
            "rocm" => Ok(Backend::Rocm),
            _ => Err(format!("Unknown backend: {}", s)),
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[non_exhaustive]
#[serde(rename_all = "lowercase")]
pub enum Dependencies {
    #[serde(rename = "cutlass_2_10")]
    Cutlass2_10,
    #[serde(rename = "cutlass_3_5")]
    Cutlass3_5,
    #[serde(rename = "cutlass_3_6")]
    Cutlass3_6,
    #[serde(rename = "cutlass_3_8")]
    Cutlass3_8,
    #[serde(rename = "cutlass_3_9")]
    Cutlass3_9,
    Torch,
}

impl TryFrom<v1::Build> for Build {
    type Error = eyre::Error;

    fn try_from(build: v1::Build) -> Result<Self> {
        let universal = build
            .torch
            .as_ref()
            .map(|torch| torch.universal)
            .unwrap_or(false);
        Ok(Self {
            general: General::from(build.general, universal),
            torch: build.torch.map(Into::into),
            kernels: convert_kernels(build.kernels)?,
        })
    }
}

impl General {
    fn from(general: v1::General, universal: bool) -> Self {
        Self {
            name: general.name,
            universal,
        }
    }
}

fn convert_kernels(v1_kernels: HashMap<String, v1::Kernel>) -> Result<HashMap<String, Kernel>> {
    let mut kernels = HashMap::new();

    for (name, kernel) in v1_kernels {
        if kernel.language == Language::CudaHipify {
            // We need to add an affix to avoid confflict with the CUDA kernel.
            let rocm_name = format!("{name}_rocm");
            if kernels.contains_key(&rocm_name) {
                bail!("Found an existing kernel with name `{rocm_name}` while expanding `{name}`")
            }

            kernels.insert(
                format!("{name}_rocm"),
                Kernel {
                    backend: Backend::Rocm,
                    cuda_capabilities: None,
                    rocm_archs: kernel.rocm_archs,
                    depends: kernel.depends.clone(),
                    include: kernel.include.clone(),
                    src: kernel.src.clone(),
                },
            );
        }

        kernels.insert(
            name,
            Kernel {
                backend: Backend::Cuda,
                cuda_capabilities: kernel.cuda_capabilities,
                rocm_archs: None,
                depends: kernel.depends,
                include: kernel.include,
                src: kernel.src,
            },
        );
    }

    Ok(kernels)
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
