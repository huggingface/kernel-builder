use std::collections::HashSet;
use std::env;
use std::io::Write;
use std::path::PathBuf;

use eyre::{bail, Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use super::kernel_ops_identifier;
use crate::config::{Build, Dependencies, Kernel, Torch};
use crate::FileSet;

static CMAKE_UTILS: &str = include_str!("../templates/utils.cmake");
static REGISTRATION_H: &str = include_str!("../templates/registration.h");

pub fn write_torch_ext_xpu(
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
        .wrap_err("Cannot render pyproject.toml template")?;

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

    env.get_template("xpu/setup.py")
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
        .wrap_err("Cannot render setup.py template")?;

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
        .wrap_err("Cannot render _ops.py template")?;

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

    let cmake_writer = file_set.entry("CMakeLists.txt");

    render_preamble(env, name, cmake_writer)?;

    render_deps(env, build, cmake_writer)?;

    render_binding(env, torch, name, cmake_writer)?;

    for (kernel_name, kernel) in build
        .kernels
        .iter()
        .filter(|(_, kernel)| matches!(kernel, Kernel::Xpu { .. }))
    {
        render_kernel(env, kernel_name, kernel, cmake_writer)?;
    }

    render_extension(env, ops_name, cmake_writer)?;

    Ok(())
}

fn render_binding(
    env: &Environment,
    torch: &Torch,
    name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("xpu/torch-binding.cmake")
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
        deps.extend(kernel.depends());
    }

    for dep in deps {
        match dep {
            Dependencies::CutlassSycl => {
                let dpcpp_version = env::var("DPCPP_VERSION").unwrap_or("2025.1".to_string());
                let version = match dpcpp_version.as_str() {
                    "2025.0" => "3.9-0.2",
                    "2025.1" => "3.9-0.3",
                    _ => bail!(
                        "No cutlass_sycl version mapped for DPCPP_VERSION {}",
                        dpcpp_version
                    ),
                };
                env.get_template("xpu/dep-cutlass-sycl.cmake")?
                    .render_to_write(context! { version => version }, &mut *write)?;
            }
            Dependencies::Torch => (),
            _ => {
                // XPU supports CUTLASS-SYCL instead of CUTLASS
                eprintln!("Warning: XPU backend doesn't need/support dependency: {dep:?}");
            }
        }
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
        .src()
        .iter()
        .map(|src| format!("\"{src}\""))
        .collect_vec()
        .join("\n");

    let sycl_flags = match kernel {
        Kernel::Xpu { sycl_flags, .. } => sycl_flags.as_deref(),
        _ => unreachable!("Unsupported kernel type for XPU rendering"),
    };

    env.get_template("xpu/kernel.cmake")
        .wrap_err("Cannot get kernel template")?
        .render_to_write(
            context! {
                cxx_flags => kernel.cxx_flags().map(|flags| flags.join(";")),
                sycl_flags => sycl_flags.map(|flags| flags.join(";")),
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

pub fn render_extension(env: &Environment, ops_name: &str, write: &mut impl Write) -> Result<()> {
    env.get_template("xpu/torch-extension.cmake")
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
    env.get_template("xpu/preamble.cmake")
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
