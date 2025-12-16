use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct Metadata {
    python_depends: Vec<String>,
}

impl Metadata {
    pub fn new(python_depends: impl Into<Vec<String>>) -> Self {
        Self {
            python_depends: python_depends.into(),
        }
    }
}
