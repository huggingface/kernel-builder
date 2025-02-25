# This script creates the necessary files for a new kernel example in the specified directory.
#
# Example Usage:
# $ uv run scripts/init-kernel.py activation
#
# Created directory: activation
#
#   activation/
#     ├── relu_kernel/
#     │   └── relu.cu
#     ├── tests/
#     │   ├── __init__.py
#     │   └── test_relu.py
#     ├── torch-ext/
#     │   ├── relu/
#     │   │   └── __init__.py
#     │   ├── torch_binding.cpp
#     │   └── torch_binding.h
#     ├── build.toml
#     └── flake.nix
#
# ✓ Success! All files for the ReLU example have been created successfully.
#
# Next steps:
#   1. Build the kernel: cd activation && git add . && nix develop -L
#   2. Run the tests: pytest -vv tests/

import os
import argparse


class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"
    GREY = "\033[90m"


def create_file_with_content(file_path: str, content: str):
    """Creates a file at 'file_path' with the specified content."""
    directory = os.path.dirname(file_path)
    if directory and not os.path.exists(directory):
        os.makedirs(directory)

    with open(file_path, "w") as f:
        f.write(content)


# Generate a tree view of the created files
def print_tree(directory: str, prefix: str=""):
    entries = sorted(os.listdir(directory))

    # Process directories first, then files
    dirs = [e for e in entries if os.path.isdir(os.path.join(directory, e))]
    files = [e for e in entries if os.path.isfile(os.path.join(directory, e))]

    # Process all items except the last one
    count = len(dirs) + len(files)

    # Print directories
    for i, dirname in enumerate(dirs):
        is_last_dir = i == len(dirs) - 1 and len(files) == 0
        connector = "└── " if is_last_dir else "├── "
        print(
            f"    {prefix}{connector}{Colors.BOLD}{Colors.BLUE}{dirname}/{Colors.ENDC}"
        )

        # Prepare the prefix for the next level
        next_prefix = prefix + ("    " if is_last_dir else "│   ")
        print_tree(os.path.join(directory, dirname), next_prefix)

    # Print files
    for i, filename in enumerate(files):
        is_last = i == len(files) - 1
        connector = "└── " if is_last else "├── "
        file_color = ""

        print(f"    {prefix}{connector}{file_color}{filename}{Colors.ENDC}")


def main():
    # Create argument parser
    parser = argparse.ArgumentParser(
        description="Create ReLU example files in the specified directory"
    )
    parser.add_argument(
        "target_dir", help="Target directory where files will be created"
    )
    args = parser.parse_args()

    # Get the target directory from arguments
    target_dir = args.target_dir

    # Create the target directory if it doesn't exist
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
        print(
            f"\n{Colors.CYAN}{Colors.BOLD}Created directory: {Colors.BOLD}{target_dir}{Colors.ENDC}\n"
        )

    # Define the file structure with file paths and content
    files = {
        # build.toml
        os.path.join(
            target_dir, "build.toml"
        ): """[general]
name = "relu"

[torch]
src = [
  "torch-ext/torch_binding.cpp",
  "torch-ext/torch_binding.h"
]

[kernel.activation]
cuda-capabilities = [ "7.0", "7.2", "7.5", "8.0", "8.6", "8.7", "8.9", "9.0" ]
src = [
  "relu_kernel/relu.cu",
]
depends = [ "torch" ]
""",
        # flake.nix
        os.path.join(
            target_dir, "flake.nix"
        ): """{
  description = "Flake for ReLU kernel";

  inputs = {
    kernel-builder.url = "git+ssh://git@github.com/huggingface/kernel-builder";
  };

  outputs =
    {
      self,
      kernel-builder,
    }:
    kernel-builder.lib.genFlakeOutputs ./.;

    nixConfig = {
      extra-substituters = [ "https://kernel-builder.cachix.org" ];
      extra-trusted-public-keys = [ "kernel-builder.cachix.org-1:JCt71vSCqW9tnmOsUigxf7tVLztjYxQ198FI/j8LrFQ=" ];
    };
}
""",
        # relu_kernel/relu.cu
        os.path.join(
            target_dir, "relu_kernel/relu.cu"
        ): """#include <ATen/cuda/CUDAContext.h>
#include <c10/cuda/CUDAGuard.h>
#include <torch/all.h>

#include <cmath>

__global__ void relu_kernel(float *__restrict__ out,
                            float const *__restrict__ input,
                            const int d) {
  const int64_t token_idx = blockIdx.x;
  for (int64_t idx = threadIdx.x; idx < d; idx += blockDim.x) {
    auto x = input[token_idx * d + idx];
    out[token_idx * d + idx] = x > 0.0f ? x : 0.0f;
  }
}

void relu(torch::Tensor &out,
          torch::Tensor const &input)
{
  TORCH_CHECK(input.scalar_type() == at::ScalarType::Float &&
                  input.scalar_type() == at::ScalarType::Float,
              "relu_kernel only supports float32");

  int d = input.size(-1);
  int64_t num_tokens = input.numel() / d;
  dim3 grid(num_tokens);
  dim3 block(std::min(d, 1024));
  const at::cuda::OptionalCUDAGuard device_guard(device_of(input));
  const cudaStream_t stream = at::cuda::getCurrentCUDAStream();
  relu_kernel<<<grid, block, 0, stream>>>(out.data_ptr<float>(),
                                          input.data_ptr<float>(), d);
}
""",
        # tests/__init__.py
        os.path.join(target_dir, "tests/__init__.py"): "",
        # tests/test_relu.py
        os.path.join(
            target_dir, "tests/test_relu.py"
        ): """import torch
import torch.nn.functional as F

import relu


def test_relu():
    x = torch.randn(1024, 1024, dtype=torch.float32, device="cuda")
    torch.testing.assert_allclose(F.relu(x), relu.relu(x))
""",
        # torch-ext/relu/__init__.py
        os.path.join(
            target_dir, "torch-ext/relu/__init__.py"
        ): """from typing import Optional

import torch

from ._ops import ops


def relu(x: torch.Tensor, out: Optional[torch.Tensor] = None) -> torch.Tensor:
    if out is None:
        out = torch.empty_like(x)
    ops.relu(out, x)
    return out
""",
        # torch-ext/torch_binding.cpp
        os.path.join(
            target_dir, "torch-ext/torch_binding.cpp"
        ): """#include <torch/library.h>

#include "registration.h"
#include "torch_binding.h"

TORCH_LIBRARY_EXPAND(TORCH_EXTENSION_NAME, ops) {
  ops.def("relu(Tensor! out, Tensor input) -> ()");
  ops.impl("relu", torch::kCUDA, &relu);
}

REGISTER_EXTENSION(TORCH_EXTENSION_NAME)
""",
        # torch-ext/torch_binding.h
        os.path.join(
            target_dir, "torch-ext/torch_binding.h"
        ): """#pragma once

#include <torch/torch.h>

void relu(torch::Tensor &out, torch::Tensor const &input);""",
    }

    for file_path, content in files.items():
        create_file_with_content(file_path, content)

    print(f"  {Colors.BOLD}{target_dir}/{Colors.ENDC}")
    print_tree(target_dir)

    print(
        f"\n{Colors.GREEN}{Colors.BOLD}✓ Success!{Colors.ENDC} All files for the ReLU example have been created successfully."
    )

    print(f"\n{Colors.CYAN}{Colors.BOLD}Next steps:{Colors.ENDC}")
    print(
        f"  {Colors.YELLOW}1.{Colors.ENDC} Build the kernel: {Colors.BOLD}cd {target_dir} && git add . && nix develop -L{Colors.ENDC}"
    )
    print(
        f"  {Colors.YELLOW}2.{Colors.ENDC} Run the tests: {Colors.BOLD}pytest -vv tests/{Colors.ENDC}"
    )
    print("")


if __name__ == "__main__":
    main()
