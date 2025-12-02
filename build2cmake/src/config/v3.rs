use std::{
    collections::{BTreeSet, HashMap},
    fmt::Display,
    path::PathBuf,
    str::FromStr,
};

use eyre::Result;
use itertools::Itertools;
use serde::{Deserialize, Serialize};

use crate::version::Version;

use super::{common::Dependency, v2};

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub general: General,
    pub torch: Option<Torch>,

    #[serde(rename = "kernel", default)]
    pub kernels: HashMap<String, Kernel>,
}

impl Build {
    pub fn is_noarch(&self) -> bool {
        self.kernels.is_empty()
    }

    pub fn supports_backend(&self, backend: &Backend) -> bool {
        self.general.backends.contains(backend)
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct General {
    pub name: String,

    pub backends: Vec<Backend>,

    pub cuda: Option<CudaGeneral>,

    pub hub: Option<Hub>,

    pub python_depends: Option<Vec<PythonDependency>>,
}

impl General {
    /// Name of the kernel as a Python extension.
    pub fn python_name(&self) -> String {
        self.name.replace("-", "_")
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct CudaGeneral {
    pub minver: Option<Version>,
    pub maxver: Option<Version>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct Hub {
    pub repo_id: Option<String>,
    pub branch: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum PythonDependency {
    Einops,
    NvidiaCutlassDsl,
}

impl Display for PythonDependency {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PythonDependency::Einops => write!(f, "einops"),
            PythonDependency::NvidiaCutlassDsl => write!(f, "nvidia-cutlass-dsl"),
        }
    }
}

#[derive(Debug, Deserialize, Clone, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Torch {
    pub include: Option<Vec<String>>,
    pub minver: Option<Version>,
    pub maxver: Option<Version>,
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
                    .map(|ext| format!("\"**/*.{ext}\""))
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
#[serde(deny_unknown_fields, rename_all = "kebab-case", tag = "backend")]
pub enum Kernel {
    #[serde(rename_all = "kebab-case")]
    Cpu {
        cxx_flags: Option<Vec<String>>,
        depends: Vec<Dependency>,
        include: Option<Vec<String>>,
        src: Vec<String>,
    },
    #[serde(rename_all = "kebab-case")]
    Cuda {
        cuda_capabilities: Option<Vec<String>>,
        cuda_flags: Option<Vec<String>>,
        cuda_minver: Option<Version>,
        cxx_flags: Option<Vec<String>>,
        depends: Vec<Dependency>,
        include: Option<Vec<String>>,
        src: Vec<String>,
    },
    #[serde(rename_all = "kebab-case")]
    Metal {
        cxx_flags: Option<Vec<String>>,
        depends: Vec<Dependency>,
        include: Option<Vec<String>>,
        src: Vec<String>,
    },
    #[serde(rename_all = "kebab-case")]
    Rocm {
        cxx_flags: Option<Vec<String>>,
        depends: Vec<Dependency>,
        rocm_archs: Option<Vec<String>>,
        hip_flags: Option<Vec<String>>,
        include: Option<Vec<String>>,
        src: Vec<String>,
    },
    #[serde(rename_all = "kebab-case")]
    Xpu {
        cxx_flags: Option<Vec<String>>,
        depends: Vec<Dependency>,
        sycl_flags: Option<Vec<String>>,
        include: Option<Vec<String>>,
        src: Vec<String>,
    },
}

impl Kernel {
    pub fn cxx_flags(&self) -> Option<&[String]> {
        match self {
            Kernel::Cpu { cxx_flags, .. }
            | Kernel::Cuda { cxx_flags, .. }
            | Kernel::Metal { cxx_flags, .. }
            | Kernel::Rocm { cxx_flags, .. }
            | Kernel::Xpu { cxx_flags, .. } => cxx_flags.as_deref(),
        }
    }

    pub fn include(&self) -> Option<&[String]> {
        match self {
            Kernel::Cpu { include, .. }
            | Kernel::Cuda { include, .. }
            | Kernel::Metal { include, .. }
            | Kernel::Rocm { include, .. }
            | Kernel::Xpu { include, .. } => include.as_deref(),
        }
    }

    pub fn backend(&self) -> Backend {
        match self {
            Kernel::Cpu { .. } => Backend::Cpu,
            Kernel::Cuda { .. } => Backend::Cuda,
            Kernel::Metal { .. } => Backend::Metal,
            Kernel::Rocm { .. } => Backend::Rocm,
            Kernel::Xpu { .. } => Backend::Xpu,
        }
    }

    pub fn depends(&self) -> &[Dependency] {
        match self {
            Kernel::Cpu { depends, .. }
            | Kernel::Cuda { depends, .. }
            | Kernel::Metal { depends, .. }
            | Kernel::Rocm { depends, .. }
            | Kernel::Xpu { depends, .. } => depends,
        }
    }

    pub fn src(&self) -> &[String] {
        match self {
            Kernel::Cpu { src, .. }
            | Kernel::Cuda { src, .. }
            | Kernel::Metal { src, .. }
            | Kernel::Rocm { src, .. }
            | Kernel::Xpu { src, .. } => src,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub enum Backend {
    Cpu,
    Cuda,
    Metal,
    Rocm,
    Xpu,
}

impl Display for Backend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Backend::Cpu => write!(f, "cpu"),
            Backend::Cuda => write!(f, "cuda"),
            Backend::Metal => write!(f, "metal"),
            Backend::Rocm => write!(f, "rocm"),
            Backend::Xpu => write!(f, "xpu"),
        }
    }
}

impl FromStr for Backend {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "cpu" => Ok(Backend::Cpu),
            "cuda" => Ok(Backend::Cuda),
            "metal" => Ok(Backend::Metal),
            "rocm" => Ok(Backend::Rocm),
            "xpu" => Ok(Backend::Xpu),
            _ => Err(format!("Unknown backend: {s}")),
        }
    }
}

impl TryFrom<v2::Build> for Build {
    type Error = eyre::Error;

    fn try_from(build: v2::Build) -> Result<Self> {
        let kernels: HashMap<String, Kernel> = build
            .kernels
            .into_iter()
            .map(|(k, v)| (k, v.into()))
            .collect();

        let backends = if build.general.universal {
            vec![
                Backend::Cpu,
                Backend::Cuda,
                Backend::Metal,
                Backend::Rocm,
                Backend::Xpu,
            ]
        } else {
            let backend_set: BTreeSet<Backend> =
                kernels.values().map(|kernel| kernel.backend()).collect();
            backend_set.into_iter().collect()
        };

        Ok(Self {
            general: General::from_v2(build.general, backends),
            torch: build.torch.map(Into::into),
            kernels,
        })
    }
}

impl General {
    fn from_v2(general: v2::General, backends: Vec<Backend>) -> Self {
        let cuda = if general.cuda_minver.is_some() || general.cuda_maxver.is_some() {
            Some(CudaGeneral {
                minver: general.cuda_minver,
                maxver: general.cuda_maxver,
            })
        } else {
            None
        };

        Self {
            name: general.name,
            backends,
            cuda,
            hub: general.hub.map(Into::into),
            python_depends: general
                .python_depends
                .map(|deps| deps.into_iter().map(Into::into).collect()),
        }
    }
}

impl From<v2::Hub> for Hub {
    fn from(hub: v2::Hub) -> Self {
        Self {
            repo_id: hub.repo_id,
            branch: hub.branch,
        }
    }
}

impl From<v2::PythonDependency> for PythonDependency {
    fn from(dep: v2::PythonDependency) -> Self {
        match dep {
            v2::PythonDependency::Einops => PythonDependency::Einops,
            v2::PythonDependency::NvidiaCutlassDsl => PythonDependency::NvidiaCutlassDsl,
        }
    }
}

impl From<v2::Torch> for Torch {
    fn from(torch: v2::Torch) -> Self {
        Self {
            include: torch.include,
            minver: torch.minver,
            maxver: torch.maxver,
            pyext: torch.pyext,
            src: torch.src,
        }
    }
}

impl From<v2::Kernel> for Kernel {
    fn from(kernel: v2::Kernel) -> Self {
        match kernel {
            v2::Kernel::Cpu {
                cxx_flags,
                depends,
                include,
                src,
            } => Kernel::Cpu {
                cxx_flags,
                depends,
                include,
                src,
            },
            v2::Kernel::Cuda {
                cuda_capabilities,
                cuda_flags,
                cuda_minver,
                cxx_flags,
                depends,
                include,
                src,
            } => Kernel::Cuda {
                cuda_capabilities,
                cuda_flags,
                cuda_minver,
                cxx_flags,
                depends,
                include,
                src,
            },
            v2::Kernel::Metal {
                cxx_flags,
                depends,
                include,
                src,
            } => Kernel::Metal {
                cxx_flags,
                depends,
                include,
                src,
            },
            v2::Kernel::Rocm {
                cxx_flags,
                depends,
                rocm_archs,
                hip_flags,
                include,
                src,
            } => Kernel::Rocm {
                cxx_flags,
                depends,
                rocm_archs,
                hip_flags,
                include,
                src,
            },
            v2::Kernel::Xpu {
                cxx_flags,
                depends,
                sycl_flags,
                include,
                src,
            } => Kernel::Xpu {
                cxx_flags,
                depends,
                sycl_flags,
                include,
                src,
            },
        }
    }
}
