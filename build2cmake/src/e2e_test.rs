use insta::assert_snapshot;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::process::Command;
use tempfile::tempdir;

#[test]
fn test_generate_torch_command() -> Result<(), Box<dyn std::error::Error>> {
    // Setup test environment
    let temp_dir = tempdir()?;
    let temp_path = temp_dir.path();
    fs::copy("../examples/relu/build.toml", temp_path.join("build.toml"))?;

    // Run CLI command
    let output = Command::new("cargo")
        .args([
            "run",
            "--",
            "generate-torch",
            &temp_path.join("build.toml").to_string_lossy(),
            "--ops-id",
            "test_ops_id",
            "--force",
        ])
        .output()?;

    // Check success
    assert!(
        output.status.success(),
        "Command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    // Test generated CMakeLists.txt
    let cmake_path = temp_path.join("CMakeLists.txt");
    assert!(cmake_path.exists(), "CMakeLists.txt not generated");
    assert_snapshot!("cmake_lists", read_and_normalize(&cmake_path)?);

    // Test all generated C++ files
    for entry in fs::read_dir(temp_path)?.filter_map(Result::ok) {
        let path = entry.path();
        if has_extension(&path, &["cpp", "h"]) {
            let filename = path.file_name().unwrap().to_string_lossy();
            assert_snapshot!(format!("file_{}", filename), read_and_normalize(&path)?);
        }
    }

    Ok(())
}

// Helper functions
fn read_and_normalize(path: &Path) -> Result<String, Box<dyn std::error::Error>> {
    let mut content = String::new();
    File::open(path)?.read_to_string(&mut content)?;
    Ok(content.replace("\r\n", "\n").trim().to_string())
}

fn has_extension(path: &Path, exts: &[&str]) -> bool {
    path.extension()
        .map_or(false, |ext| exts.contains(&ext.to_string_lossy().as_ref()))
}
