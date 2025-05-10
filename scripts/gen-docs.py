# /// script
# dependencies = ["toml", "minijinja"]
# ///
import toml
import sys
import os
import glob
import re
from minijinja import Environment


def extract_ops(file_path):
    ops = []
    with open(file_path, "r") as f:
        content = f.read()
        # Find TORCH_LIBRARY_EXPAND blocks
        lib_blocks = re.findall(
            r"TORCH_LIBRARY_EXPAND\([^)]+\)([^}]+)}", content, re.DOTALL
        )
        for block in lib_blocks:
            # Extract ops.def lines
            op_defs = re.findall(r"ops\.def\(\"([^\"]+)\"", block)
            ops.extend(op_defs)
    return ops


def main():
    if len(sys.argv) < 2:
        print("Usage: script.py <project_directory>")
        return

    project_dir = sys.argv[1]

    # Read build.toml or return if not found
    build_config_path = os.path.join(project_dir, "build.toml")
    if not os.path.exists(build_config_path):
        print(f"Error: build.toml not found at {build_config_path}")
        return
    try:
        build_config = toml.load(build_config_path)
        print(f"Successfully parsed build configuration from {build_config_path}")

    except Exception as e:
        print(f"Error parsing build.toml: {e}")
        return

    if not build_config:
        return

    # Get all kernels from the config
    config_kernels = build_config.get("kernel", {})

    kernels = []
    for kernel_name, kernel_info in config_kernels.items():
        kernels.append(
            {
                "name": kernel_name,
                "cuda-capabilities": kernel_info.get("cuda-capabilities", []),
                "src": kernel_info.get("src", []),
                "dependencies": kernel_info.get("depends", []),
            }
        )

    # Find torch-ext directory and extract all ops
    ops = []
    torch_ext_dirs = glob.glob(
        os.path.join(project_dir, "**/torch-ext"), recursive=True
    )
    for torch_ext_dir in torch_ext_dirs:
        for file in glob.glob(os.path.join(torch_ext_dir, "**/*.cpp"), recursive=True):
            for op in extract_ops(file):
                relative_file = "../" + os.path.relpath(file, project_dir)
                ops.append(dict(op=op, file=relative_file))

    # Prepare template data
    template_data = {
        "project_name": os.path.basename(project_dir),
        "build_config": {"kernels": kernels},
        "ops": ops,
    }

    # Render template
    env = Environment(
        templates={
            "doc_template": """
# `{{ project_name }}` Documentation

> __Generated on 2025-03-25__

## Table of Contents

- [Project Overview](#project-overview)
- [Build Configuration](#build-configuration)
  - [Kernels](#kernels){% for kernel_info in build_config.get("kernels", {}) %}\n    - [{{ kernel_info.get("name") }}](#{{ kernel_info.get("name") }}){% endfor %}
  - [Operations](#operations){% for op in ops %}\n    - [{{ op.get("op") }}]({{ op.get("file") }}){% endfor %}

## Project Overview
{{ project_name }} is a CUDA kernel project.

## Build Configuration

### Kernels
{% for kernel_info in build_config.get("kernels", {}) %}
#### {{ kernel_info.get("name") }}

**CUDA Capabilities:**
- `{{ kernel_info.get("cuda-capabilities", []) }}`

**Source Files:**
{% for source in kernel_info.get("src", []) %}
- `{{ source }}`
{% endfor %}

**Dependencies:**
{% for dep in kernel_info.get("dependencies", []) %}
- `{{ dep }}`
{% endfor %}
{% endfor %}

### operations
{% for op in ops %}
```cpp
{{ op.get("op") }}
```
[defined]({{ op.get("file") }})

{% endfor %}
"""
        }
    )
    output = env.render_template("doc_template", **template_data)

    # Write output file
    project_name = os.path.basename(os.path.abspath(project_dir))
    output_dir = os.path.join(project_dir, "docs")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"{project_name}.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(output)


if __name__ == "__main__":
    main()
