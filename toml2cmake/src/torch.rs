use std::{
    collections::HashSet,
    fs::File,
    io::{BufWriter, Write},
    path::{Path, PathBuf},
};

use eyre::{bail, eyre, Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use crate::config::{Build, Dependencies, Kernel, Torch};

static CMAKE_UTILS: &str = include_str!("cmake/utils.cmake");

pub fn write_torch_ext(env: &Environment, build: &Build, target_dir: PathBuf) -> Result<()> {
    let torch_ext = match build.torch.as_ref() {
        Some(torch_ext) => torch_ext,
        None => bail!("Build configuration does not have `torch` section"),
    };

    write_cmake(env, build, torch_ext, &target_dir)?;

    let ext_name = format!(
        "_{}_{}",
        torch_ext.name,
        build.general.version.replace(".", "_")
    );

    write_setup_py(
        env,
        torch_ext,
        &ext_name,
        &build.general.version,
        &target_dir,
    )?;

    write_ops_py(env, torch_ext, &ext_name, &target_dir)?;

    write_pyproject_toml(env, &target_dir)?;

    Ok(())
}

fn write_pyproject_toml(env: &Environment, target_dir: &Path) -> Result<()> {
    let mut path = target_dir.to_owned();
    path.push("pyproject.toml");
    let writer = BufWriter::new(
        File::create(&path)
            .wrap_err_with(|| format!("Cannot create `{}`", path.to_string_lossy()))?,
    );

    env.get_template("pyproject.toml")
        .wrap_err("Cannot get pyproject.toml template")?
        .render_to_write(context! {}, writer)
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_setup_py(
    env: &Environment,
    torch: &Torch,
    ext_name: &str,
    version: &str,
    target_dir: &Path,
) -> Result<()> {
    let mut path = target_dir.to_owned();
    path.push("setup.py");
    let writer = BufWriter::new(
        File::create(&path)
            .wrap_err_with(|| format!("Cannot create `{}`", path.to_string_lossy()))?,
    );

    env.get_template("setup.py")
        .wrap_err("Cannot get setup.py template")?
        .render_to_write(
            context! {
                ext_name => ext_name,
                name => torch.name,
                version => version,
                pyroot => torch.pyroot,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_ops_py(env: &Environment, torch: &Torch, ext_name: &str, target_dir: &Path) -> Result<()> {
    let mut path = target_dir.to_owned();
    path.push(&torch.pyroot);
    path.push(&torch.name);
    path.push("_ops.py");
    let writer = BufWriter::new(
        File::create(&path)
            .wrap_err_with(|| format!("Cannot create `{}`", path.to_string_lossy()))?,
    );

    env.get_template("_ops.py")
        .wrap_err("Cannot get _ops.py template")?
        .render_to_write(
            context! {
                ext_name => ext_name,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_cmake(env: &Environment, build: &Build, torch: &Torch, target_dir: &Path) -> Result<()> {
    let mut utils_path = target_dir.to_owned();
    utils_path.push("cmake");
    utils_path.push("utils.cmake");
    write_to_file(&utils_path, CMAKE_UTILS)?;

    let mut cmakelists_path = target_dir.to_owned();
    cmakelists_path.push("CMakeLists.txt");
    let mut cmake_writer = BufWriter::new(
        File::create(&cmakelists_path)
            .wrap_err_with(|| format!("Cannot create `{}`", cmakelists_path.to_string_lossy()))?,
    );

    render_preamble(env, torch, &mut cmake_writer)?;

    render_deps(env, build, &mut cmake_writer)?;

    for (kernel_name, kernel) in &build.kernels {
        render_kernel(env, kernel_name, kernel, &mut cmake_writer)?;
    }

    let ext_name = format!(
        "_{}_{}",
        torch.name,
        build.general.version.replace(".", "_")
    );

    render_extension(env, torch, &ext_name, &mut cmake_writer)?;

    Ok(())
}

fn render_deps(env: &Environment, build: &Build, write: &mut impl Write) -> Result<()> {
    let mut deps = HashSet::new();
    for kernel in build.kernels.values() {
        deps.extend(&kernel.depends);
    }

    for dep in deps {
        match dep {
            Dependencies::Cutlass => {
                env.get_template("dep-cutlass.cmake")
                    .wrap_err("Cannot get CUTLASS dependency template")?
                    .render_to_write(context! {}, &mut *write)
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
    ext_name: &str,
    write: &mut impl Write,
) -> Result<()> {
    env.get_template("torch-extension.cmake")
        .wrap_err("Cannot get Torch extension template")?
        .render_to_write(
            context! {
                includes => torch.include.as_ref().map(prefix_and_join_includes),
                ext_name => ext_name,
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

fn write_to_file(path: impl AsRef<Path>, data: &str) -> Result<()> {
    let path = path.as_ref();

    let parent = path
        .parent()
        .ok_or_else(|| eyre!("Cannot get parent of `{}`", path.to_string_lossy()))?;
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("Cannot create directory `{}`", parent.to_string_lossy()))?;

    let mut write = BufWriter::new(
        File::create(path)
            .wrap_err_with(|| format!("Cannot open `{}` for writing", path.to_string_lossy()))?,
    );
    write
        .write_all(data.as_bytes())
        .wrap_err_with(|| format!("Cannot write to `{}`", path.to_string_lossy()))
}
