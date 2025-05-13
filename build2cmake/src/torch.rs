use std::collections::HashSet;
use std::io::Write;
use std::path::{Path, PathBuf};

use eyre::{bail, Context, Result};
use git2::Repository;
use itertools::Itertools;
use minijinja::{context, Environment};
use rand::Rng;

use crate::config::{Build, Dependencies, Kernel, Torch};
use crate::FileSet;

static CMAKE_UTILS: &str = include_str!("cmake/utils.cmake");
static REGISTRATION_H: &str = include_str!("templates/registration.h");
static HIPIFY: &str = include_str!("cmake/hipify.py");
static CUDA_SUPPORTED_ARCHS_JSON: &str = include_str!("cuda_supported_archs.json");

fn random_identifier() -> String {
    // Generate a random string when no ops_id is provided
    let mut rng = rand::thread_rng();
    let build_id: u64 = rng.gen();
    base32::encode(
        base32::Alphabet::Rfc4648Lower { padding: false },
        &build_id.to_le_bytes(),
    )
}

fn git_identifier(target_dir: impl AsRef<Path>) -> Result<String> {
    let repo = Repository::discover(target_dir.as_ref()).context("Cannot open git repository")?;
    let head = repo.head()?;
    let commit = head.peel_to_commit()?;
    let rev = commit.tree_id().to_string().chars().take(7).collect();
    let dirty = !repo.statuses(None)?.is_empty();
    Ok(if dirty { format!("{rev}_dirty") } else { rev })
}

pub fn kernel_ops_identifier(
    target_dir: impl AsRef<Path>,
    name: &str,
    ops_id: Option<String>,
) -> String {
    let identifier = ops_id.unwrap_or_else(|| match git_identifier(target_dir.as_ref()) {
        Ok(rev) => rev,
        Err(_) => random_identifier(),
    });

    format!("_{name}_{identifier}")
}

fn cuda_supported_archs() -> String {
    let supported_archs: Vec<String> = serde_json::from_str(CUDA_SUPPORTED_ARCHS_JSON)
        .expect("Error parsing supported CUDA archs");
    supported_archs.join(";")
}

pub fn write_torch_ext(
    env: &Environment,
    build: &Build,
    target_dir: PathBuf,
    force: bool,
    ops_id: Option<String>,
) -> Result<()> {
    let torch_ext = match build.torch.as_ref() {
        Some(torch_ext) => torch_ext,
        None => bail!("Build configuration does not have `torch` section"),
    };

    let mut file_set = FileSet::default();

    let ops_name = kernel_ops_identifier(&target_dir, &build.general.name, ops_id);

    write_cmake(
        env,
        build,
        torch_ext,
        &build.general.name,
        &ops_name,
        &mut file_set,
    )?;

    write_setup_py(
        env,
        torch_ext,
        &build.general.name,
        &ops_name,
        &mut file_set,
    )?;

    write_ops_py(env, &build.general.name, &ops_name, &mut file_set)?;

    write_pyproject_toml(env, &mut file_set)?;

    write_torch_registration_macros(&mut file_set)?;

    file_set.write(&target_dir, force)?;

    Ok(())
}

fn write_torch_registration_macros(file_set: &mut FileSet) -> Result<()> {
    let mut path = PathBuf::new();
    path.push("torch-ext");
    path.push("registration.h");
    file_set
        .entry(path)
        .extend_from_slice(REGISTRATION_H.as_bytes());

    Ok(())
}

fn write_pyproject_toml(env: &Environment, file_set: &mut FileSet) -> Result<()> {
    let writer = file_set.entry("pyproject.toml");

    env.get_template("pyproject.toml")
        .wrap_err("Cannot get pyproject.toml template")?
        .render_to_write(context! {}, writer)
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_setup_py(
    env: &Environment,
    torch: &Torch,
    name: &str,
    ops_name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("setup.py");

    let data_globs = torch.data_globs().map(|globs| globs.join(", "));

    env.get_template("setup.py")
        .wrap_err("Cannot get setup.py template")?
        .render_to_write(
            context! {
                data_globs => data_globs,
                ops_name => ops_name,
                name => name,
                version => "0.1.0",
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_ops_py(
    env: &Environment,
    name: &str,
    ops_name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let mut path = PathBuf::new();
    path.push("torch-ext");
    path.push(name);
    path.push("_ops.py");
    let writer = file_set.entry(path);

    env.get_template("_ops.py")
        .wrap_err("Cannot get _ops.py template")?
        .render_to_write(
            context! {
                ops_name => ops_name,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_cmake(
    env: &Environment,
    build: &Build,
    torch: &Torch,
    name: &str,
    ops_name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let mut utils_path = PathBuf::new();
    utils_path.push("cmake");
    utils_path.push("utils.cmake");
    file_set
        .entry(utils_path.clone())
        .extend_from_slice(CMAKE_UTILS.as_bytes());

    let mut hipify_path = PathBuf::new();
    hipify_path.push("cmake");
    hipify_path.push("hipify.py");
    file_set
        .entry(hipify_path.clone())
        .extend_from_slice(HIPIFY.as_bytes());

    let cmake_writer = file_set.entry("CMakeLists.txt");

    render_preamble(env, name, cmake_writer)?;

    render_deps(env, build, cmake_writer)?;

    render_binding(env, torch, name, cmake_writer)?;

    for (kernel_name, kernel) in &build.kernels {
        render_kernel(env, kernel_name, kernel, cmake_writer)?;
    }

    render_extension(env, ops_name, cmake_writer)?;

    Ok(())
}

pub fn render_binding(
    env: &Environment,
    torch: &Torch,
    name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("torch-binding.cmake")
        .wrap_err("Cannot get Torch binding template")?
        .render_to_write(
            context! {
                includes => torch.include.as_ref().map(prefix_and_join_includes),
                name => name,
                src => torch.src
            },
            &mut *write,
        )
        .wrap_err("Cannot render Torch binding template")?;

    write.write_all(b"\n")?;

    Ok(())
}

fn render_deps(env: &Environment, build: &Build, write: &mut impl Write) -> Result<()> {
    let mut deps = HashSet::new();
    for kernel in build.kernels.values() {
        deps.extend(&kernel.depends);
    }

    for dep in deps {
        match dep {
            Dependencies::Cutlass2_10 => {
                env.get_template("dep-cutlass.cmake")
                    .wrap_err("Cannot get CUTLASS dependency template")?
                    .render_to_write(
                        context! {
                            version => "2.10.0",
                        },
                        &mut *write,
                    )
                    .wrap_err("Cannot render CUTLASS dependency template")?;
            }
            Dependencies::Cutlass3_5 => {
                env.get_template("dep-cutlass.cmake")
                    .wrap_err("Cannot get CUTLASS dependency template")?
                    .render_to_write(
                        context! {
                            version => "3.5.1",
                        },
                        &mut *write,
                    )
                    .wrap_err("Cannot render CUTLASS dependency template")?;
            }
            Dependencies::Cutlass3_6 => {
                env.get_template("dep-cutlass.cmake")
                    .wrap_err("Cannot get CUTLASS dependency template")?
                    .render_to_write(
                        context! {
                            version => "3.6.0",
                        },
                        &mut *write,
                    )
                    .wrap_err("Cannot render CUTLASS dependency template")?;
            }
            Dependencies::Cutlass3_8 => {
                env.get_template("dep-cutlass.cmake")
                    .wrap_err("Cannot get CUTLASS dependency template")?
                    .render_to_write(
                        context! {
                            version => "3.8.0",
                        },
                        &mut *write,
                    )
                    .wrap_err("Cannot render CUTLASS dependency template")?;
            }
            Dependencies::Torch => (),
        };
        write.write_all(b"\n")?;
    }

    Ok(())
}

pub fn render_kernel(
    env: &Environment,
    kernel_name: &str,
    kernel: &Kernel,
    write: &mut impl Write,
) -> Result<()> {
    // Easier to do in Rust than Jinja.
    let sources = kernel
        .src
        .iter()
        .map(|src| format!("\"{src}\""))
        .collect_vec()
        .join("\n");

    env.get_template("kernel.cmake")
        .wrap_err("Cannot get kernel template")?
        .render_to_write(
            context! {
                cuda_capabilities => kernel.cuda_capabilities,
                rocm_archs => kernel.rocm_archs,
                includes => kernel.include.as_ref().map(prefix_and_join_includes),
                kernel_name => kernel_name,
                language => kernel.language.to_string(),
                sources => sources,
            },
            &mut *write,
        )
        .wrap_err("Cannot render kernel template")?;

    write.write_all(b"\n")?;

    Ok(())
}

pub fn render_extension(env: &Environment, ops_name: &str, write: &mut impl Write) -> Result<()> {
    env.get_template("torch-extension.cmake")
        .wrap_err("Cannot get Torch extension template")?
        .render_to_write(
            context! {
                ops_name => ops_name,
            },
            &mut *write,
        )
        .wrap_err("Cannot render Torch extension template")?;

    write.write_all(b"\n")?;

    Ok(())
}

pub fn render_preamble(env: &Environment, name: &str, write: &mut impl Write) -> Result<()> {
    env.get_template("preamble.cmake")
        .wrap_err("Cannot get CMake prelude template")?
        .render_to_write(
            context! {
                name => name,
                cuda_supported_archs => cuda_supported_archs(),

            },
            &mut *write,
        )
        .wrap_err("Cannot render CMake prelude template")?;

    write.write_all(b"\n")?;

    Ok(())
}

fn prefix_and_join_includes<S>(includes: impl AsRef<[S]>) -> String
where
    S: AsRef<str>,
{
    includes
        .as_ref()
        .iter()
        .map(|include| format!("${{CMAKE_SOURCE_DIR}}/{}", include.as_ref()))
        .collect_vec()
        .join(";")
}
