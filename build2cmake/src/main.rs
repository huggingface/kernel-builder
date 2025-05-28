use std::{
    fs::File,
    io::{BufWriter, Read, Write},
    path::{Path, PathBuf},
};

use clap::{Parser, Subcommand};
use eyre::{bail, ensure, Context, Result};
use minijinja::Environment;

mod torch;
use torch::{write_torch_ext, write_torch_ext_metal, write_torch_universal_ext};

mod config;
use config::{Backend, Build, BuildCompat};

mod fileset;
use fileset::FileSet;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Generate CMake files for Torch extension builds.
    GenerateTorch {
        #[arg(name = "BUILD_TOML")]
        build_toml: PathBuf,

        /// The directory to write the generated files to
        /// (directory of `BUILD_TOML` when absent).
        #[arg(name = "TARGET_DIR")]
        target_dir: Option<PathBuf>,

        /// Force-overwrite existing files.
        #[arg(short, long)]
        force: bool,

        /// This is an optional unique identifier that is suffixed to the
        /// kernel name to avoid name collisions. (e.g. Git SHA)
        #[arg(long)]
        ops_id: Option<String>,

        #[arg(long)]
        backend: Option<Backend>,
    },

    /// Update a `build.toml` to the current format.
    UpdateBuild {
        #[arg(name = "BUILD_TOML")]
        build_toml: PathBuf,
    },

    /// Validate the build.toml file.
    Validate {
        #[arg(name = "BUILD_TOML")]
        build_toml: PathBuf,
    },
}

fn main() -> Result<()> {
    let args = Cli::parse();
    match args.command {
        Commands::GenerateTorch {
            backend,
            build_toml,
            force,
            target_dir,
            ops_id,
        } => generate_torch(backend, build_toml, target_dir, force, ops_id),
        Commands::UpdateBuild { build_toml } => update_build(build_toml),
        Commands::Validate { build_toml } => {
            parse_and_validate(build_toml)?;
            Ok(())
        }
    }
}

fn generate_torch(
    backend: Option<Backend>,
    build_toml: PathBuf,
    target_dir: Option<PathBuf>,
    force: bool,
    ops_id: Option<String>,
) -> Result<()> {
    let target_dir = check_or_infer_target_dir(&build_toml, target_dir)?;

    let build_compat = parse_and_validate(build_toml)?;

    if matches!(build_compat, BuildCompat::V1(_)) {
        eprintln!(
            "build.toml is in the deprecated V1 format, use `build2cmake update-build` to update."
        )
    }

    let build: Build = build_compat
        .try_into()
        .context("Cannot update build configuration")?;

    let mut env = Environment::new();
    env.set_trim_blocks(true);
    minijinja_embed::load_templates!(&mut env);

    let backend = match (backend, build.general.universal) {
        (None, true) => return write_torch_universal_ext(&env, &build, target_dir, force, ops_id),
        (Some(backend), true) => bail!("Universal kernel, cannot generate for backend {}", backend),
        (Some(backend), false) => {
            if !build.has_kernel_with_backend(&backend) {
                bail!("No kernels found for backend {}", backend);
            }

            backend
        }
        (None, false) => {
            let mut kernel_backends = build.backends();
            let backend = if let Some(backend) = kernel_backends.pop_first() {
                backend
            } else {
                bail!("No kernels found in build.toml");
            };

            if !kernel_backends.is_empty() {
                let kernel_backends: Vec<_> = build
                    .backends()
                    .into_iter()
                    .map(|backend| backend.to_string())
                    .collect();
                bail!(
                    "Multiple supported backends found in build.toml: {}. Please specify one with --backend.",
                    kernel_backends.join(", ")
                );
            }

            backend
        }
    };

    match backend {
        Backend::Cuda | Backend::Rocm => {
            write_torch_ext(&env, backend, &build, target_dir, force, ops_id)
        }
        Backend::Metal => write_torch_ext_metal(&env, &build, target_dir, force, ops_id),
    }
}

fn update_build(build_toml: PathBuf) -> Result<()> {
    let build_compat: BuildCompat = parse_and_validate(&build_toml)?;

    if matches!(build_compat, BuildCompat::V2(_)) {
        return Ok(());
    }

    let build: Build = build_compat
        .try_into()
        .context("Cannot update build configuration")?;
    let pretty_toml = toml::to_string_pretty(&build)?;

    let mut writer =
        BufWriter::new(File::create(&build_toml).wrap_err_with(|| {
            format!("Cannot open {} for writing", build_toml.to_string_lossy())
        })?);
    writer
        .write_all(pretty_toml.as_bytes())
        .wrap_err_with(|| format!("Cannot write to {}", build_toml.to_string_lossy()))?;

    Ok(())
}

fn check_or_infer_target_dir(
    build_toml: impl AsRef<Path>,
    target_dir: Option<PathBuf>,
) -> Result<PathBuf> {
    let build_toml = build_toml.as_ref();
    match target_dir {
        Some(target_dir) => {
            ensure!(
                target_dir.is_dir(),
                "`{}` is not a directory",
                target_dir.to_string_lossy()
            );
            Ok(target_dir)
        }
        None => {
            let absolute = std::path::absolute(build_toml)?;
            match absolute.parent() {
                Some(parent) => Ok(parent.to_owned()),
                None => bail!(
                    "Cannot get parent path of `{}`",
                    build_toml.to_string_lossy()
                ),
            }
        }
    }
}

fn parse_and_validate(build_toml: impl AsRef<Path>) -> Result<BuildCompat> {
    let build_toml = build_toml.as_ref();
    let mut toml_data = String::new();
    File::open(build_toml)
        .wrap_err_with(|| format!("Cannot open {} for reading", build_toml.to_string_lossy()))?
        .read_to_string(&mut toml_data)
        .wrap_err_with(|| format!("Cannot read from {}", build_toml.to_string_lossy()))?;

    let build_compat: BuildCompat = toml::from_str(&toml_data)
        .wrap_err_with(|| format!("Cannot parse TOML in {}", build_toml.to_string_lossy()))?;

    Ok(build_compat)
}
