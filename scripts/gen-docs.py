# /// script
# dependencies = [
#   "toml",
# ]
# ///
import os
import re
import toml
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Generate documentation for kernel projects"
    )
    parser.add_argument("project_path", help="Path to the kernel project root")
    parser.add_argument("--output", "-o", help="Output directory", default="docs")
    parser.add_argument(
        "--toc",
        "-t",
        help="Include table of contents",
        action="store_true",
        default=True,
    )
    return parser.parse_args()


def parse_build_config(project_path: str) -> Optional[Dict[str, Any]]:
    """Parse the build.toml configuration file."""
    build_config_path = os.path.join(project_path, "build.toml")
    if not os.path.exists(build_config_path):
        print(f"Error: build.toml not found at {build_config_path}")
        return None

    try:
        config = toml.load(build_config_path)
        print(f"Successfully parsed build configuration from {build_config_path}")
        return config
    except Exception as e:
        print(f"Error parsing build.toml: {e}")
        return None


def extract_function_signature(content: str, func_name: str) -> str:
    """Extract the full function signature for better documentation."""
    # Look for the function definition
    pattern = rf"(?:__global__ void|void|template\s*<.*?>\s*__global__ void|template\s*<.*?>\s*void)\s+{func_name}\s*\([^\)]*\)"
    match = re.search(pattern, content, re.DOTALL)
    if match:
        signature = match.group(0).strip()
        # Remove trailing comments on each line
        signature_lines = signature.split("\n")
        signature_lines = [line.split("//")[0].strip() for line in signature_lines]
        signature = "\n".join(signature_lines)
        # Clean up the signature
        signature = re.sub(r"\s+", " ", signature)
        return signature
    return func_name


def extract_function_params(content: str, func_name: str) -> List[Dict[str, str]]:
    """Extract function parameters with their types."""
    pattern = rf"(?:__global__ void|void|template\s*<.*?>\s*__global__ void|template\s*<.*?>\s*void)\s+{func_name}\s*\(([^\)]*)\)"
    match = re.search(pattern, content, re.DOTALL)
    params = []

    if match:
        param_str = match.group(1).strip()
        # Remove trailing comments on each line
        param_str_lines = param_str.split("\n")
        param_str_lines = [line.split("//")[0].strip() for line in param_str_lines]
        param_str = "\n".join(param_str_lines)

        if param_str:
            # Split by commas, but handle nested template parameters
            param_parts = []
            current_part = ""
            template_depth = 0

            for char in param_str:
                if char == "," and template_depth == 0:
                    param_parts.append(current_part.strip())
                    current_part = ""
                else:
                    if char == "<":
                        template_depth += 1
                    elif char == ">":
                        template_depth -= 1
                    current_part += char

            if current_part:
                param_parts.append(current_part.strip())

            for part in param_parts:
                # Extract type and name
                parts = part.split()
                if len(parts) >= 2:
                    param_type = " ".join(parts[:-1])
                    param_name = parts[-1].rstrip(",")
                    # Clean param name (remove pointers/references from name)
                    param_name = param_name.lstrip("*&")
                    params.append({"type": param_type, "name": param_name})

    return params


def parse_kernel_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """Extract kernel configuration from the build.toml."""
    kernel_config = {}

    # Extract kernels section
    for key, value in config.items():
        if key == "kernel":
            kernel_config = value
            break

    return kernel_config


def extract_kernel_docs(
    project_path: str, kernel_config: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Extract documentation from kernel source files."""
    kernel_info = []
    source_files = []

    # Collect source files from kernel config first
    for kernel_name, kernel_data in kernel_config.items():
        if "src" in kernel_data and isinstance(kernel_data["src"], list):
            for src_file in kernel_data["src"]:
                file_path = os.path.join(project_path, src_file)
                if os.path.exists(file_path):
                    source_files.append(Path(file_path))

    # Also collect all other source files
    for ext in [".cu", ".h", ".cpp", ".cuh"]:
        extra_files = [
            p for p in Path(project_path).glob(f"**/*{ext}") if p not in source_files
        ]
        source_files.extend(extra_files)

    source_files = sorted(set(source_files))

    for source_file in source_files:
        rel_path = os.path.relpath(source_file, project_path)
        file_info = {"file": rel_path, "functions": []}

        try:
            with open(source_file, "r", encoding="utf-8") as f:
                content = f.read()

            # Extract kernel declarations with comments
            kernel_pattern = r"/\*\*\s*(.*?)\s*\*/\s*(?:__global__ void|template\s*<.*?>\s*__global__ void)\s+(\w+)"
            function_pattern = r"/\*\*\s*(.*?)\s*\*/\s*(?:template\s*<.*?>\s*)?(?:inline\s+)?(?:__host__\s+)?(?:__device__\s+)?(?:\w+\s+)+(\w+)\s*\("

            # Extract kernels without comments too
            simple_kernel_pattern = r"__global__\s+void\s+(\w+)\s*\("
            simple_function_pattern = r"(?:__host__|__device__|__host__\s+__device__|__device__\s+__host__|void)\s+(\w+)\s*\("

            # Process kernels with comments
            for match in re.finditer(kernel_pattern, content, re.DOTALL):
                comment = match.group(1).strip().replace("*", "").strip()
                name = match.group(2)
                signature = extract_function_signature(content, name)
                params = extract_function_params(content, name)

                file_info["functions"].append(
                    {
                        "name": name,
                        "type": "kernel",
                        "doc": comment,
                        "signature": signature,
                        "params": params,
                    }
                )

            # Process regular functions with comments
            for match in re.finditer(function_pattern, content, re.DOTALL):
                comment = match.group(1).strip().replace("*", "").strip()
                name = match.group(2)
                # Skip if already processed as kernel
                if any(f["name"] == name for f in file_info["functions"]):
                    continue
                signature = extract_function_signature(content, name)
                params = extract_function_params(content, name)

                file_info["functions"].append(
                    {
                        "name": name,
                        "type": "function",
                        "doc": comment,
                        "signature": signature,
                        "params": params,
                    }
                )

            # Process kernels without comments
            for match in re.finditer(simple_kernel_pattern, content):
                name = match.group(1)
                # Skip if already processed
                if any(f["name"] == name for f in file_info["functions"]):
                    continue
                signature = extract_function_signature(content, name)
                params = extract_function_params(content, name)

                file_info["functions"].append(
                    {
                        "name": name,
                        "type": "kernel",
                        "doc": "",
                        "signature": signature,
                        "params": params,
                    }
                )

            # Process simple functions without comments
            for match in re.finditer(simple_function_pattern, content):
                name = match.group(1)
                # Skip if already processed
                if any(f["name"] == name for f in file_info["functions"]):
                    continue
                signature = extract_function_signature(content, name)
                params = extract_function_params(content, name)

                file_info["functions"].append(
                    {
                        "name": name,
                        "type": "function",
                        "doc": "",
                        "signature": signature,
                        "params": params,
                    }
                )

            # Only add files that have documented functions
            if file_info["functions"]:
                kernel_info.append(file_info)

        except Exception as e:
            print(f"Error processing {source_file}: {e}")

    return kernel_info


def generate_toc(sections):
    """Generate a table of contents from section headers."""
    toc = ["## Table of Contents", ""]
    for section in sections:
        indent = "  " * (section["level"] - 1)
        link = (
            section["title"]
            .lower()
            .replace(" ", "-")
            .replace(".", "")
            .replace("(", "")
            .replace(")", "")
            .replace(":", "")
        )
        toc.append(f"{indent}- [{section['title']}](#{link})")
    return toc


def format_parameter_table(params):
    """Format function parameters as a markdown table."""
    if not params:
        return ""

    table = ["| Parameter | Type |", "|-----------|------|"]
    for param in params:
        table.append(f"| `{param['name']}` | `{param['type']}` |")

    return "\n".join(table)


def generate_markdown(
    project_path: str,
    config: Dict[str, Any],
    kernel_info: List[Dict[str, Any]],
    include_toc: bool = True,
) -> str:
    """Generate markdown documentation from parsed information."""
    project_name = os.path.basename(os.path.abspath(project_path))
    sections = []

    # Extract project name from config if available
    if config and "general" in config and "name" in config["general"]:
        project_name = config["general"]["name"]

    # Start with title and metadata
    lines = [
        f"# `{project_name}` Documentation",
        "",
        f"*Generated on {datetime.now().strftime('%Y-%m-%d')}*",
        "",
    ]

    # Add project overview
    sections.append({"title": "Project Overview", "level": 2})
    lines.extend(["## Project Overview", ""])

    # If we have a description in the config, use it
    if config and "general" in config and "description" in config.get("general", {}):
        lines.append(config["general"]["description"])
    else:
        lines.append(f"{project_name} is a CUDA kernel project.")
    lines.append("")

    # Add configuration details
    if config:
        sections.append({"title": "Build Configuration", "level": 2})
        lines.append("## Build Configuration")
        lines.append("")

        # Extract kernel configurations
        kernel_configs = parse_kernel_config(config)
        if kernel_configs:
            sections.append({"title": "Kernels", "level": 3})
            lines.append("### Kernels")
            lines.append("")

            for kernel_name, kernel_data in kernel_configs.items():
                lines.append(f"#### {kernel_name}")
                lines.append("")

                if "cuda-capabilities" in kernel_data:
                    capabilities = ", ".join(kernel_data["cuda-capabilities"])
                    lines.append("**CUDA Capabilities:**")
                    lines.append(f"- `[{capabilities}]`")
                    lines.append("")

                if "src" in kernel_data:
                    lines.append("**Source Files:**")
                    for src_file in kernel_data["src"]:
                        lines.append(f"- `{src_file}`")
                    lines.append("")

                if "depends" in kernel_data:
                    lines.append("**Dependencies:**")
                    for dep in kernel_data["depends"]:
                        lines.append(f"- `{dep}`")
                    lines.append("")

    # Add source documentation
    if kernel_info:
        sections.append({"title": "API Documentation", "level": 2})
        lines.append("## API Documentation")
        lines.append("")

        for file_info in kernel_info:
            sections.append({"title": file_info["file"], "level": 3})
            lines.append(f"### {file_info['file']}")
            lines.append("")

            # Add functions and kernels
            for func in sorted(file_info["functions"], key=lambda x: x["name"]):
                func_type = "Kernel" if func["type"] == "kernel" else "Function"
                sections.append({"title": f"{func['name']} ({func_type})", "level": 4})
                lines.append(f"#### {func['name']} ({func_type})")
                lines.append("")

                # Add function signature in code block
                lines.append("```cpp")
                lines.append(func["signature"])
                lines.append("```")
                lines.append("")

                # Add documentation if it exists
                if func["doc"]:
                    lines.append(func["doc"])
                    lines.append("")

                # Add parameter table if not in short mode
                if func["params"]:
                    lines.append("**Parameters:**")
                    lines.append("")
                    lines.append(format_parameter_table(func["params"]))
                    lines.append("")

    # Insert table of contents after the title if requested
    if include_toc:
        toc = generate_toc(sections)
        lines = lines[:3] + [""] + toc + [""] + lines[3:]

    return "\n".join(lines)


def main():
    """Main function to run the documentation generator."""
    args = parse_args()
    project_path = args.project_path

    # Parse build configuration
    config = parse_build_config(project_path)

    # Parse kernel configs from build.toml
    kernel_config = parse_kernel_config(config) if config else {}

    # Extract kernel documentation
    kernel_info = extract_kernel_docs(project_path, kernel_config)

    # Generate documentation
    markdown_content = generate_markdown(
        project_path,
        config,
        kernel_info,
        include_toc=args.toc,
    )

    # Create output directory if it doesn't exist
    output_dir = os.path.join(project_path, args.output)
    os.makedirs(output_dir, exist_ok=True)

    # Write output file
    project_name = os.path.basename(os.path.abspath(project_path))
    if config and "general" in config and "name" in config["general"]:
        project_name = config["general"]["name"]

    output_path = os.path.join(output_dir, f"{project_name}.md")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(markdown_content)

    print(f"Documentation generated at {output_path}")


if __name__ == "__main__":
    main()
