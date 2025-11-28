use std::path::PathBuf;

use eyre::{Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use crate::{
    config::{General, Torch},
    FileSet,
};

pub fn write_pyproject_toml(
    env: &Environment,
    general: &General,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("pyproject.toml");

    let python_dependencies = general
        .python_depends
        .as_ref()
        .unwrap_or(&vec![])
        .iter()
        .map(|d| format!("\"{d}\""))
        .join(", ");

    env.get_template("pyproject.toml")
        .wrap_err("Cannot get pyproject.toml template")?
        .render_to_write(
            context! {
                python_dependencies => python_dependencies,
            },
            writer,
        )
        .wrap_err("Cannot render kernel template")?;

    Ok(())
}

pub fn render_utils(env: &Environment, torch: &Torch, file_set: &mut FileSet) -> Result<()> {
    let mut utils_path = PathBuf::new();
    utils_path.push("cmake");
    utils_path.push("utils.cmake");
    let writer = file_set.entry(utils_path);

    env.get_template("utils.cmake")
        .wrap_err("Cannot get utils template")?
        .render_to_write(
            context! {
                link_flags => torch.link_flags.as_ref().map(|flags| flags.join(";")),
            },
            writer,
        )
        .wrap_err("Cannot render utils template")?;

    Ok(())
}
