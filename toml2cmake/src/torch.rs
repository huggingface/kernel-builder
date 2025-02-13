use std::collections::HashSet;
use std::io::Write;
use std::path::PathBuf;

use eyre::{bail, Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};
use rand::Rng;

use crate::config::{Build, Dependencies, Kernel, Torch};
use crate::FileSet;

static CMAKE_UTILS: &str = include_str!("cmake/utils.cmake");

fn kernel_ops_identifier(name: &str) -> String {
    let mut rng = rand::thread_rng();
    let build_id: u64 = rng.gen();
    let build_string = base32::encode(
        base32::Alphabet::Rfc4648Lower { padding: false },
        &build_id.to_le_bytes(),
    );

    format!("_{}_{}", name, build_string)
}

pub fn write_torch_ext(
    env: &Environment,
    build: &Build,
    target_dir: PathBuf,
    force: bool,
) -> Result<()> {
    let torch_ext = match build.torch.as_ref() {
        Some(torch_ext) => torch_ext,
        None => bail!("Build configuration does not have `torch` section"),
    };

    let mut file_set = FileSet::default();

    let ops_name = kernel_ops_identifier(&torch_ext.name);

    write_cmake(env, build, torch_ext, &ops_name, &mut file_set)?;

    write_setup_py(
        env,
        torch_ext,
        &ops_name,
        &build.general.version,
        &mut file_set,
    )?;

    write_ops_py(env, torch_ext, &ops_name, &mut file_set)?;

    write_pyproject_toml(env, &mut file_set)?;

    file_set.write(&target_dir, force)?;

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
    ops_name: &str,
    version: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("setup.py");

    // Globs for files that are not Python files.
    let data_globs = match torch.pyext.as_ref() {
        Some(exts) => {
            let globs = exts
                .iter()
                .filter(|&ext| ext != "py" && ext != "pyi")
                .map(|ext| format!("\"**/*.{}\"", ext))
                .collect_vec();
            if globs.is_empty() {
                None
            } else {
                Some(globs.join(", "))
            }
        }

        None => None,
    };

    env.get_template("setup.py")
        .wrap_err("Cannot get setup.py template")?
        .render_to_write(
            context! {
                data_globs => data_globs,
                ops_name => ops_name,
                name => torch.name,
                version => version,
                pyroot => torch.pyroot,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_ops_py(
    env: &Environment,
    torch: &Torch,
    ops_name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let mut path = PathBuf::new();
    path.push(&torch.pyroot);
    path.push(&torch.name);
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
    ops_name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let mut utils_path = PathBuf::new();
    utils_path.push("cmake");
    utils_path.push("utils.cmake");
    file_set
        .entry(utils_path.clone())
        .extend_from_slice(CMAKE_UTILS.as_bytes());

    let cmake_writer = file_set.entry("CMakeLists.txt");

    render_preamble(env, torch, cmake_writer)?;

    render_deps(env, build, cmake_writer)?;

    for (kernel_name, kernel) in &build.kernels {
        render_kernel(env, kernel_name, kernel, cmake_writer)?;
    }

    render_extension(env, torch, ops_name, cmake_writer)?;

    Ok(())
}

fn render_deps(env: &Environment, build: &Build, write: &mut impl Write) -> Result<()> {
    let mut deps = HashSet::new();
    for kernel in build.kernels.values() {
        deps.extend(&kernel.depends);
    }

    for dep in deps {
        match dep {
            Dependencies::Cutlass35 => {
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
            Dependencies::Cutlass36 => {
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
                capabilities => kernel.capabilities,
                includes => kernel.include.as_ref().map(prefix_and_join_includes),
                kernel_name => kernel_name,
                sources => sources,
            },
            &mut *write,
        )
        .wrap_err("Cannot render kernel template")?;

    write.write_all(b"\n")?;

    Ok(())
}

pub fn render_extension(
    env: &Environment,
    torch: &Torch,
    ops_name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("torch-extension.cmake")
        .wrap_err("Cannot get Torch extension template")?
        .render_to_write(
            context! {
                includes => torch.include.as_ref().map(prefix_and_join_includes),
                ops_name => ops_name,
                name => torch.name,
                src => torch.src
            },
            &mut *write,
        )
        .wrap_err("Cannot render Torch extension template")?;

    write.write_all(b"\n")?;

    Ok(())
}

pub fn render_preamble(env: &Environment, torch: &Torch, write: &mut impl Write) -> Result<()> {
    env.get_template("preamble.cmake")
        .wrap_err("Cannot get CMake prelude template")?
        .render_to_write(context! { name => torch.name }, &mut *write)
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
