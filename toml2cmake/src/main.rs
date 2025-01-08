use std::{
    fs::File,
    io::Read,
    path::{Path, PathBuf},
};

use clap::{Parser, Subcommand};
use eyre::{bail, ensure, Context, Result};
use minijinja::Environment;

mod torch;
use torch::write_torch_ext;

mod config;
use config::Build;

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

        #[arg(name = "TARGET_DIR")]
        target_dir: Option<PathBuf>,
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
            build_toml,
            target_dir,
        } => generate_torch(build_toml, target_dir),
        Commands::Validate { build_toml } => validate(build_toml),
    }
}

fn generate_torch(build_toml: PathBuf, target_dir: Option<PathBuf>) -> Result<()> {
    let target_dir = check_or_infer_target_dir(&build_toml, target_dir)?;

    let mut toml_data = String::new();
    File::open(&build_toml)
        .wrap_err_with(|| format!("Cannot open {} for reading", build_toml.to_string_lossy()))?
        .read_to_string(&mut toml_data)
        .wrap_err_with(|| format!("Cannot read from {}", build_toml.to_string_lossy()))?;

    let build: Build = toml::from_str(&toml_data)
        .wrap_err_with(|| format!("Cannot parse TOML in {}", build_toml.to_string_lossy()))?;

    let mut env = Environment::new();
    minijinja_embed::load_templates!(&mut env);

    write_torch_ext(&env, &build, target_dir)?;

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

fn validate(build_toml: PathBuf) -> Result<()> {
    let mut toml_data = String::new();
    File::open(&build_toml)
        .wrap_err_with(|| format!("Cannot open {} for reading", build_toml.to_string_lossy()))?
        .read_to_string(&mut toml_data)
        .wrap_err_with(|| format!("Cannot read from {}", build_toml.to_string_lossy()))?;

    let _: Build = toml::from_str(&toml_data)
        .wrap_err_with(|| format!("Cannot parse TOML in {}", build_toml.to_string_lossy()))?;

    Ok(())
}
