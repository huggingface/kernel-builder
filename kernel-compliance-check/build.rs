use std::env;
use std::fs;
use std::io::Read as _;
use std::path::Path;

fn main() {
    // Print for debugging and to ensure the script reruns when changed
    println!("cargo:rerun-if-changed=build.rs");

    // Get the output directory from Cargo
    let out_dir = env::var("OUT_DIR").expect("OUT_DIR not set");
    let dest_path = Path::new(&out_dir).join("variants_data.rs");

    println!("cargo:warning=Build script is running!");
    println!("cargo:warning=Output directory: {out_dir}");

    // Fetch the remote JSON file
    println!("cargo:warning=Fetching remote variants JSON...");
    let url = "https://raw.githubusercontent.com/huggingface/kernel-builder/refs/heads/main/build-variants.json";

    let mut remote_variants_json = String::new();

    match ureq::get(url).call() {
        Ok(resp) => {
            match resp.into_reader().read_to_string(&mut remote_variants_json) {
                Ok(_) => {
                    println!(
                        "cargo:warning=Successfully fetched remote variants ({} bytes)",
                        remote_variants_json.len()
                    );
                }
                Err(e) => {
                    println!("cargo:warning=Error reading response body: {e}");
                    // Instead of returning an empty JSON, provide fallback content
                    remote_variants_json = String::from("{}");
                }
            }
        }
        Err(e) => {
            println!("cargo:warning=Error fetching remote variants: {e}");
            // Provide fallback content
            remote_variants_json = String::from("{}");
        }
    };

    // Create output directory if it doesn't exist (though Cargo should have created it)
    fs::create_dir_all(Path::new(&out_dir)).expect("Failed to create output directory");

    // Write the complete module with all necessary functions
    let output = format!(
        r###"use serde_json::Value;
use std::sync::OnceLock;

pub const VARIANTS_DATA: &str = r#"{}"#;

// Use OnceLock to lazily initialize the parsed JSON data
static VARIANTS_CACHE: OnceLock<Value> = OnceLock::new();

// Function to get the parsed JSON data
pub fn get_variants() -> &'static Value {{
    VARIANTS_CACHE.get_or_init(|| {{
        serde_json::from_str(VARIANTS_DATA).unwrap_or_else(|_| {{
            // Provide a fallback empty object if parsing fails
            serde_json::json!({{}})
        }})
    }})
}}

#[allow(clippy::missing_panics_doc)]
pub fn get_cuda_variants() -> Vec<String> {{
    let variants = get_variants();
    // get all cuda
    let mut cuda_variants = Vec::new();
    for arch in variants.as_object().unwrap().keys() {{
        if let Some(arch_data) = variants.get(arch) {{
            if let Some(cuda_array) = arch_data.get("cuda").and_then(|v| v.as_array()) {{
                cuda_variants.extend(
                    cuda_array
                        .iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect::<Vec<String>>(),
                );
            }}
        }}
    }}

    // Return empty vector if not found
    if cuda_variants.is_empty() {{
        return Vec::new();
    }}
    // Remove duplicates
    cuda_variants.sort();
    cuda_variants.dedup();
    cuda_variants
}}

#[allow(clippy::missing_panics_doc)]
pub fn get_rocm_variants() -> Vec<String> {{
    let variants = get_variants();

    let mut rocm_variants = Vec::new();
    for arch in variants.as_object().unwrap().keys() {{
        if let Some(arch_data) = variants.get(arch) {{
            if let Some(rocm_array) = arch_data.get("rocm").and_then(|v| v.as_array()) {{
                rocm_variants.extend(
                    rocm_array
                        .iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect::<Vec<String>>(),
                );
            }}
        }}
    }}
    // Return empty vector if not found
    if rocm_variants.is_empty() {{
        return Vec::new();
    }}
    // Remove duplicates
    rocm_variants.sort();
    rocm_variants.dedup();
    rocm_variants
}}

"###,
        // Escape any problematic characters in the JSON string
        remote_variants_json
            .replace('\\', "\\\\")
            .replace("\"#", "\\\"#")
    );

    println!("cargo:warning=Writing output to: {dest_path:?}");
    fs::write(&dest_path, &output).expect("Failed to write variants_data.rs");

    println!("cargo:warning=Build script completed successfully");
}
