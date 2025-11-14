use std::path::PathBuf;

use eyre::{Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use crate::{
    config::{Build, General, Torch},
    fileset::FileSet,
    torch::kernel_ops_identifier,
};

pub fn write_torch_ext_universal(
    env: &Environment,
    build: &Build,
    target_dir: PathBuf,
    ops_id: Option<String>,
) -> Result<FileSet> {
    let mut file_set = FileSet::default();

    let ops_name = kernel_ops_identifier(&target_dir, &build.general.python_name(), ops_id);

    write_ops_py(env, &build.general.python_name(), &ops_name, &mut file_set)?;
    write_pyproject_toml(env, build.torch.as_ref(), &build.general, &mut file_set)?;

    Ok(file_set)
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

    env.get_template("universal/_ops.py")
        .wrap_err("Cannot get _ops-universal.py template")?
        .render_to_write(
            context! {
                ops_name => ops_name,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

fn write_pyproject_toml(
    env: &Environment,
    torch: Option<&Torch>,
    general: &General,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("pyproject.toml");

    let name = &general.name;
    let data_globs = torch.and_then(|torch| torch.data_globs().map(|globs| globs.join(", ")));
    let python_dependencies = general
        .python_depends
        .as_ref()
        .unwrap_or(&vec![])
        .iter()
        .map(|d| format!("\"{d}\""))
        .join(", ");

    env.get_template("universal/pyproject.toml")
        .wrap_err("Cannot get universal pyproject.toml template")?
        .render_to_write(
            context! {
                data_globs => data_globs,
                python_dependencies => python_dependencies,
                name => name,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}
