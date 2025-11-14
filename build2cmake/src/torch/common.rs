use eyre::{Context, Result};
use itertools::Itertools;
use minijinja::{context, Environment};

use crate::{config::General, FileSet};

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
