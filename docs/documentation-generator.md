# Documentation Generator

This tool helps you generate consistent documentation for your CUDA kernel projects built with kernel-builder. It analyzes source files and build configuration to create structured Markdown documentation.

## Features

- Extracts documentation from CUDA, C++, and header files
- Parses build configuration from build.toml
- Identifies kernels and function definitions with their parameters
- Generates Markdown documentation with a table of contents
- Includes build settings and project information

## Usage

```bash
# Generate documentation for a kernel project
python scripts/gen-docs.py /path/to/your/kernel/project

# Specify custom output directory (default is "docs")
python scripts/gen-docs.py /path/to/your/kernel/project --output custom-docs
```

## Comment Format

For best results, document your kernels and functions using the following format:

```cpp
/**
 * This is a description of the kernel or function.
 * 
 * Any additional details about the implementation or usage can go here.
 */
__global__ void my_kernel(float* input, float* output, int size) {
    // kernel implementation
}
```

The generator will extract this documentation and include it in the generated files.

## Output Structure

The generated documentation includes:

1. **Table of Contents** - Navigation for all documentation sections
2. **Project Overview** - Basic information about the project (from build.toml if available)
3. **Build Configuration** - Settings from build.toml including:
   - Kernel definitions
   - CUDA capabilities
   - Source files
   - Dependencies
4. **API Documentation** - Documentation for each source file:
   - Function and kernel signatures
   - Parameter tables with types
   - Documentation comments

## Example

Given a project with the following structure:

```
my_kernel/
├── build.toml
├── kernel.cu
└── torch-ext/
    └── ...
```

Running the documentation generator:

```bash
python scripts/gen-docs.py my_kernel
```

Will produce `my_kernel.md` in the `my_kernel/docs` directory.