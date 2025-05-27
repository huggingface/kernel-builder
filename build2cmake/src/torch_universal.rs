use std::path::PathBuf;

use eyre::{Context, Result};
use minijinja::{context, Environment};

use crate::{
    config::{Build, Torch},
    fileset::FileSet,
    torch::kernel_ops_identifier,
};

pub fn write_torch_universal_ext(
    env: &Environment,
    build: &Build,
    target_dir: PathBuf,
    force: bool,
    ops_id: Option<String>,
) -> Result<()> {
    let mut file_set = FileSet::default();

    let ops_name = kernel_ops_identifier(&target_dir, &build.general.name, ops_id);

    write_ops_py(env, &build.general.name, &ops_name, &mut file_set)?;
    write_pyproject_toml(
        env,
        build.torch.as_ref(),
        &build.general.name,
        &mut file_set,
    )?;

    file_set.write(&target_dir, force)?;

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

    env.get_template("_ops-universal.py")
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
    name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("pyproject.toml");

    let data_globs = torch.and_then(|torch| torch.data_globs().map(|globs| globs.join(", ")));

    env.get_template("pyproject_universal.toml")
        .wrap_err("Cannot get universal pyproject.toml template")?
        .render_to_write(
            context! {
                data_globs => data_globs,
                name => name,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}
