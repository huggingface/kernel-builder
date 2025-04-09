//! Functions for checking kernel ABI compatibility.

mod manylinux;
pub use manylinux::{check_manylinux, ManylinuxViolation};

mod python_abi;
pub use python_abi::{check_python_abi, PythonAbiViolation};

mod version;
pub use version::Version;
