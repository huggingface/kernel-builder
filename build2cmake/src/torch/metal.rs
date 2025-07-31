use std::{io::Write, path::PathBuf};

use eyre::{bail, Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use super::kernel_ops_identifier;
use crate::{
    config::{Build, Kernel, Torch},
    fileset::FileSet,
};

static CMAKE_UTILS: &str = include_str!("../templates/utils.cmake");
static REGISTRATION_H: &str = include_str!("../templates/registration.h");
static COMPILE_METAL_CMAKE: &str = include_str!("../templates/metal/compile-metal.cmake");
static METALLIB_TO_HEADER_PY: &str = include_str!("../templates/metal/metallib_to_header.py");

pub fn write_torch_ext_metal(
    env: &Environment,
    build: &Build,
    target_dir: PathBuf,
    ops_id: Option<String>,
) -> Result<FileSet> {
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

    Ok(file_set)
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

    let mut compile_metal_path = PathBuf::new();
    compile_metal_path.push("cmake");
    compile_metal_path.push("compile-metal.cmake");
    file_set
        .entry(compile_metal_path)
        .extend_from_slice(COMPILE_METAL_CMAKE.as_bytes());

    let mut metallib_to_header_path = PathBuf::new();
    metallib_to_header_path.push("cmake");
    metallib_to_header_path.push("metallib_to_header.py");
    file_set
        .entry(metallib_to_header_path)
        .extend_from_slice(METALLIB_TO_HEADER_PY.as_bytes());

    let cmake_writer = file_set.entry("CMakeLists.txt");

    render_preamble(env, name, cmake_writer)?;

    // Add deps once we have any non-CUDA deps.
    // render_deps(env, build, cmake_writer)?;

    render_binding(env, torch, name, cmake_writer)?;

    for (kernel_name, kernel) in build
        .kernels
        .iter()
        .filter(|(_, kernel)| matches!(kernel, Kernel::Metal { .. }))
    {
        render_kernel(env, kernel_name, kernel, cmake_writer)?;
    }

    render_extension(env, name, ops_name, cmake_writer)?;

    Ok(())
}

fn render_binding(
    env: &Environment,
    torch: &Torch,
    name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("metal/torch-binding.cmake")
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

pub fn render_extension(
    env: &Environment,
    name: &str,
    ops_name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("metal/torch-extension.cmake")
        .wrap_err("Cannot get Torch extension template")?
        .render_to_write(
            context! {
                name => name,
                ops_name => ops_name,
            },
            &mut *write,
        )
        .wrap_err("Cannot render Torch extension template")?;

    write.write_all(b"\n")?;

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
        .src()
        .iter()
        .map(|src| format!("\"{src}\""))
        .collect_vec()
        .join("\n");

    env.get_template("metal/kernel.cmake")
        .wrap_err("Cannot get kernel template")?
        .render_to_write(
            context! {
                cxx_flags => kernel.cxx_flags().map(|flags| flags.join(";")),
                includes => kernel.include().map(prefix_and_join_includes),
                kernel_name => kernel_name,
                sources => sources,
            },
            &mut *write,
        )
        .wrap_err("Cannot render kernel template")?;

    write.write_all(b"\n")?;

    Ok(())
}

fn render_preamble(env: &Environment, name: &str, write: &mut impl Write) -> Result<()> {
    env.get_template("metal/preamble.cmake")
        .wrap_err("Cannot get CMake prelude template")?
        .render_to_write(
            context! {
                name => name,
            },
            &mut *write,
        )
        .wrap_err("Cannot render CMake prelude template")?;

    write.write_all(b"\n")?;

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

    env.get_template("metal/setup.py")
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

fn write_torch_registration_macros(file_set: &mut FileSet) -> Result<()> {
    let mut path = PathBuf::new();
    path.push("torch-ext");
    path.push("registration.h");
    file_set
        .entry(path)
        .extend_from_slice(REGISTRATION_H.as_bytes());

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
