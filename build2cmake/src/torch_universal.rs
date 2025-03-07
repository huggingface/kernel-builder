use std::path::PathBuf;

use eyre::{bail, Context, Result};
use minijinja::{context, Environment};

use crate::{
    config::{Build, Torch},
    fileset::FileSet,
};

pub fn write_torch_universal_ext(
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

    write_pyproject_toml(env, torch_ext, &build.general.name, &mut file_set)?;

    file_set.write(&target_dir, force)?;

    Ok(())
}

fn write_pyproject_toml(
    env: &Environment,
    torch: &Torch,
    name: &str,
    file_set: &mut FileSet,
) -> Result<()> {
    let writer = file_set.entry("pyproject.toml");

    let data_globs = torch.data_globs().map(|globs| globs.join(", "));

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
