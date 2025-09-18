use std::ffi::OsString;
use std::fs;
use std::str::FromStr;

use kernel_abi_check::{
    MacOSViolation, ManylinuxViolation, PythonAbiViolation, Version, check_macos, check_manylinux,
};
use object::Object as ObjectTrait;
use pyo3::Bound as PyBound;
use pyo3::exceptions::PyIOError;
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;

/// Object file that can be validated.
#[pyclass(name = "ObjectFile")]
struct PyObjectFile {
    filename: OsString,
    data: Vec<u8>,
}

impl PyObjectFile {
    fn parse_file(&self) -> PyResult<object::File> {
        object::File::parse(&*self.data).map_err(|err| {
            PyValueError::new_err(format!(
                "Cannot parse object file `{}`: {}",
                self.filename.to_string_lossy(),
                err
            ))
        })
    }
}

#[pymethods]
impl PyObjectFile {
    /// Create a new `ObjectFile` from a path.
    #[new]
    fn new(filename: OsString) -> PyResult<Self> {
        let data = fs::read(&filename).map_err(|err| {
            PyIOError::new_err(format!(
                "Cannot open object file `{}`: {}",
                filename.to_string_lossy(),
                err
            ))
        })?;

        Ok(Self { filename, data })
    }

    /// Check Python ABI compatibility for this object file  
    fn check_python_abi(&self, abi_version: String, py: Python) -> PyResult<Vec<Py<PyAny>>> {
        let file = self.parse_file()?;

        let python_abi = Version::from_str(&abi_version).map_err(|err| {
            PyValueError::new_err(format!(
                "Cannot parse Python ABI version `{abi_version}`: {err}",
            ))
        })?;

        let violations =
            kernel_abi_check::check_python_abi(&python_abi, file.format(), file.symbols())
                .map_err(|err| {
                    PyValueError::new_err(format!(
                        "Cannot check Python ABI for `{}`: {}",
                        self.filename.to_string_lossy(),
                        err
                    ))
                })?;

        let mut result = Vec::new();
        for violation in violations {
            let py_violation: Py<PyAny> = match violation {
                PythonAbiViolation::IncompatibleAbi3Symbol { name, added } => {
                    Py::new(py, PyIncompatibleAbi3Symbol { name, added })?.into()
                }
                PythonAbiViolation::NonAbi3Symbol { name } => {
                    Py::new(py, PyNonAbi3Symbol { name })?.into()
                }
            };
            result.push(py_violation);
        }
        Ok(result)
    }

    /// Check manylinux compatibility for this object file
    fn check_manylinux(&self, manylinux_version: String, py: Python) -> PyResult<Vec<Py<PyAny>>> {
        let file = self.parse_file()?;

        let violations = check_manylinux(
            &manylinux_version,
            file.architecture(),
            file.endianness(),
            file.symbols(),
        )
        .map_err(|err| {
            PyValueError::new_err(format!(
                "Cannot check manylinux for `{}`: {}",
                self.filename.to_string_lossy(),
                err
            ))
        })?;

        let mut result = Vec::new();
        for violation in violations {
            let py_violation: Py<PyAny> = match violation {
                ManylinuxViolation::Symbol { name, dep, version } => {
                    Py::new(py, PyManylinuxSymbolViolation { name, dep, version })?.into()
                }
            };
            result.push(py_violation);
        }
        Ok(result)
    }

    /// Check macOS compatibility for this object file
    fn check_macos(&self, macos_version: String, py: Python) -> PyResult<Vec<Py<PyAny>>> {
        let file = self.parse_file()?;

        let macos_ver = Version::from_str(&macos_version).map_err(|err| {
            PyValueError::new_err(format!(
                "Cannot parse macOS version `{macos_version}`: {err}",
            ))
        })?;

        let violations = check_macos(&file, &macos_ver).map_err(|err| {
            PyValueError::new_err(format!(
                "Cannot check macOS for `{}`: {}",
                self.filename.to_string_lossy(),
                err
            ))
        })?;

        let mut result = Vec::new();
        for violation in violations {
            let py_violation: Py<PyAny> = match violation {
                MacOSViolation::MissingMinOS => Py::new(py, PyMissingMinOS)?.into(),
                MacOSViolation::IncompatibleMinOS { version } => {
                    Py::new(py, PyIncompatibleMinOS { version })?.into()
                }
            };
            result.push(py_violation);
        }
        Ok(result)
    }
}

/// Incompatible ABI3 symbol violation
#[pyclass(name = "IncompatibleAbi3Symbol")]
struct PyIncompatibleAbi3Symbol {
    name: String,
    added: Version,
}

#[pymethods]
impl PyIncompatibleAbi3Symbol {
    #[getter]
    fn name(&self) -> &str {
        &self.name
    }

    #[getter]
    fn version_added(&self) -> String {
        self.added.to_string()
    }

    fn __repr__(&self) -> String {
        format!(
            "IncompatibleAbi3Symbol(name='{}', version_added='{}')",
            self.name, self.added
        )
    }
}

/// Non-ABI3 symbol violation
#[pyclass(name = "NonAbi3Symbol")]
struct PyNonAbi3Symbol {
    name: String,
}

#[pymethods]
impl PyNonAbi3Symbol {
    #[getter]
    fn name(&self) -> &str {
        &self.name
    }

    fn __repr__(&self) -> String {
        format!("NonAbi3Symbol(name='{}')", self.name)
    }
}

/// Manylinux symbol violation
#[pyclass(name = "ManylinuxSymbolViolation")]
struct PyManylinuxSymbolViolation {
    name: String,
    dep: String,
    version: String,
}

#[pymethods]
impl PyManylinuxSymbolViolation {
    #[getter]
    fn name(&self) -> &str {
        &self.name
    }

    #[getter]
    fn dep(&self) -> &str {
        &self.dep
    }

    #[getter]
    fn version(&self) -> &str {
        &self.version
    }

    fn __repr__(&self) -> String {
        format!(
            "ManylinuxSymbolViolation(name='{}', dep='{}', version='{}')",
            self.name, self.dep, self.version
        )
    }
}

/// Missing minimum OS version violation
#[pyclass(name = "MissingMinOS")]
struct PyMissingMinOS;

#[pymethods]
impl PyMissingMinOS {
    fn __repr__(&self) -> String {
        "MissingMinOS()".to_string()
    }
}

/// Incompatible minimum OS version violation
#[pyclass(name = "IncompatibleMinOS")]
struct PyIncompatibleMinOS {
    version: Version,
}

#[pymethods]
impl PyIncompatibleMinOS {
    #[getter]
    fn version(&self) -> String {
        self.version.to_string()
    }

    fn __repr__(&self) -> String {
        format!("IncompatibleMinOS(version='{}')", self.version)
    }
}

#[pyo3::pymodule(name = "kernel_abi_check")]
fn kernel_abi_check_py(m: &PyBound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<PyObjectFile>()?;

    // Python ABI violation classes
    m.add_class::<PyIncompatibleAbi3Symbol>()?;
    m.add_class::<PyNonAbi3Symbol>()?;

    // Manylinux violation classes
    m.add_class::<PyManylinuxSymbolViolation>()?;

    // macOS violation classes
    m.add_class::<PyMissingMinOS>()?;
    m.add_class::<PyIncompatibleMinOS>()?;

    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
