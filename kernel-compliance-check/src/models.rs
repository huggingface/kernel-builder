use std::fmt;

use clap::{Parser, Subcommand, ValueEnum};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CompliantError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Repository not found: {0}")]
    RepositoryNotFound(String),

    #[error("Build directory not found in repository: {0}")]
    BuildDirNotFound(String),

    #[error("Failed to fetch repository: {0}")]
    FetchError(String),

    #[error("Failed to parse object file: {0}")]
    ObjectParseError(String),

    #[error("Failed to check ABI compatibility: {0}")]
    AbiCheckError(String),

    #[error("Failed to serialize JSON: {0}")]
    SerializationError(String),

    #[error("Failed to fetch variants: {0}")]
    VariantsFetchError(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Unknown error: {0}")]
    Other(String),
}

/// Hugging Face kernel compliance checker
#[derive(Parser)]
#[command(author, version, about)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Format {
    Console,
    Json,
}

impl Format {
    #[must_use]
    pub fn is_json(&self) -> bool {
        matches!(self, Format::Json)
    }
}

#[derive(Subcommand)]
pub enum Commands {
    /// Check repository compliance and ABI compatibility
    Check {
        /// Repository IDs or names (comma-separated)
        #[arg(value_name = "REPOS")]
        repos: String,

        /// Manylinux version to check against
        #[arg(short, long, default_value = "manylinux_2_28")]
        manylinux: String,

        /// Python ABI version to check against
        #[arg(short, long, default_value = "3.9")]
        python_abi: String,

        /// Revision (branch, tag, or commit hash) to use when fetching
        #[arg(short, long, default_value = "main")]
        revision: String,

        /// Show all variants in a long format. Default is compact output.
        #[arg(long, default_value_t = false)]
        long: bool,

        /// Force fetch the repository if not found locally
        #[arg(long, alias = "force", default_value_t = false)]
        force_fetch: bool,

        /// Show ABI violations in the output. Default is to only show compatibility status.
        #[arg(long, default_value_t = false)]
        show_violations: bool,

        /// Format of the output. Default is console
        #[arg(long, default_value = "console")]
        format: Format,
    },
}

/// Structured representation of build variants
#[derive(Debug, Deserialize)]
pub struct VariantsConfig {
    #[serde(rename = "x86_64-linux")]
    pub x86_64_linux: ArchConfig,
    #[serde(rename = "aarch64-linux")]
    pub aarch64_linux: ArchConfig,
}

#[derive(Debug, Deserialize)]
pub struct ArchConfig {
    pub cuda: Vec<String>,
    #[serde(default)]
    #[cfg(feature = "enable_rocm")]
    pub rocm: Vec<String>,
    #[cfg(not(feature = "enable_rocm"))]
    #[serde(default, skip)]
    _rocm: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variant {
    pub torch_version: String,
    pub cxx_abi: String,
    pub compute_framework: String,
    pub arch: String,
    pub os: String,
}

impl fmt::Display for Variant {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}-{}-{}-{}-{}",
            self.torch_version, self.cxx_abi, self.compute_framework, self.arch, self.os
        )
    }
}

impl Variant {
    #[must_use]
    pub fn from_name(name: &str) -> Option<Self> {
        let parts: Vec<&str> = name.split('-').collect();
        if parts.len() < 5 {
            return None;
        }
        // Format: torch{major}{minor}-{cxxabi}-{compute_framework}-{arch}-{os}
        Some(Variant {
            torch_version: parts[0].to_string(),
            cxx_abi: parts[1].to_string(),
            compute_framework: parts[2].to_string(),
            arch: parts[3].to_string(),
            os: parts[4].to_string(),
        })
    }
}

#[derive(Serialize)]
pub struct RepoErrorResponse {
    pub repository: String,
    pub status: String,
    pub error: String,
}

#[derive(Serialize)]
pub struct RepositoryCheckResult {
    pub repository: String,
    pub status: String,
    pub build_status: BuildStatus,
    pub abi_status: AbiStatus,
}

#[derive(Serialize)]
pub struct BuildStatus {
    pub summary: String,
    pub cuda: CudaStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rocm: Option<RocmStatus>,
}

#[derive(Serialize)]
pub struct CudaStatus {
    pub compatible: bool,
    pub present: Vec<String>,
    pub missing: Vec<String>,
}

#[derive(Serialize)]
pub struct RocmStatus {
    pub compatible: bool,
    pub present: Vec<String>,
    pub missing: Vec<String>,
}

#[derive(Serialize)]
pub struct AbiStatus {
    pub compatible: bool,
    pub manylinux_version: String,
    pub python_abi_version: String,
    pub variants: Vec<VariantCheckOutput>,
}

#[derive(Serialize)]
pub struct VariantCheckOutput {
    pub name: String,
    pub compatible: bool,
    pub has_shared_objects: bool,
    pub violations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedObjectViolation {
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariantResult {
    pub name: String,
    pub is_compatible: bool,
    pub violations: Vec<SharedObjectViolation>,
    pub has_shared_objects: bool,
}

#[derive(Debug, Clone)]
pub struct AbiCheckResult {
    pub overall_compatible: bool,
    pub variants: Vec<VariantResult>,
    pub manylinux_version: String,
    pub python_abi_version: kernel_abi_check::Version,
}
