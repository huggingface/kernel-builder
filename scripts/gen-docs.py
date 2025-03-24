# /// script
# dependencies = [
#   "toml",
#   "clang",
# ]
# ///
from clang.cindex import Config
import clang.cindex
from clang.cindex import CursorKind
from typing import Dict, List, Optional, Any, Tuple
import os
from pathlib import Path
import argparse
from datetime import datetime
import toml


Config.set_library_file("/Library/Developer/CommandLineTools/usr/lib/libclang.dylib")
Config.set_compatibility_check(False)


def get_function_declarations(file_path):
    """
    Extract all function declarations from a C++ file.

    Args:
        file_path (str): Path to the C++ file

    Returns:
        list: List of dictionaries containing function information
    """
    # Initialize clang index
    index = clang.cindex.Index.create()

    # Parse the file
    translation_unit = index.parse(file_path)

    # Check for parsing errors
    if not translation_unit:
        print(f"Error parsing {file_path}")
        return []

    functions = []

    # Helper function to recursively traverse the AST
    def traverse_ast(cursor, parent=None):
        # Check if the cursor represents a function declaration
        if cursor.kind == CursorKind.FUNCTION_DECL:
            # Get function return type
            return_type = cursor.type.get_result().spelling

            # Get function name
            func_name = cursor.spelling

            # Get function parameters
            params = []
            for param in cursor.get_arguments():
                params.append({"name": param.spelling, "type": param.type.spelling})

            # Get function location
            location = cursor.location
            file_path = location.file.name if location.file else "Unknown"
            line = location.line
            column = location.column

            # Check if the function has a body
            has_body = any(
                c.kind == CursorKind.COMPOUND_STMT for c in cursor.get_children()
            )

            # Determine if it's a declaration or definition
            func_type = "definition" if has_body else "declaration"

            # Add function info to our list
            functions.append(
                {
                    "name": func_name,
                    "return_type": return_type,
                    "parameters": params,
                    "location": {"file": file_path, "line": line, "column": column},
                    "type": func_type,
                }
            )

        # Recursively process children
        for child in cursor.get_children():
            traverse_ast(child, cursor)

    # Start traversing from the translation unit cursor
    traverse_ast(translation_unit.cursor)

    return functions


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
        extra_files = []
        for p in Path(project_path).glob(f"**/*{ext}"):
            # avoid adding `torch-ext` files
            if "torch-ext" in str(p):
                continue
            if p not in source_files:
                extra_files.append(p)

        source_files.extend(extra_files)

    source_files = sorted(set(source_files))

    for source_file in source_files:
        rel_path = os.path.relpath(source_file, project_path)
        file_info = {"file": rel_path, "functions": []}

        functions = get_function_declarations(source_file)
        for func in functions:
            signature = f"{func['return_type']} {func['name']}("
            signature += (
                ", ".join([f"{p['type']} {p['name']}" for p in func["parameters"]])
                + ")"
            )
            file_info["functions"].append(
                dict(
                    name=func["name"],
                    type=func["type"],
                    doc="",
                    signature=signature,
                    params=[
                        dict(name=p["name"], type=p["type"], doc="")
                        for p in func["parameters"]
                    ],
                )
            )

        if len(file_info["functions"]) > 0:
            kernel_info.append(file_info)

    return kernel_info


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


def parse_kernel_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """Extract kernel configuration from the build.toml."""
    kernel_config = {}

    # Extract kernels section
    for key, value in config.items():
        if key == "kernel":
            kernel_config = value
            break

    return kernel_config


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
