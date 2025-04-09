# Writing Hub kernels with kernel-builder

## Introduction

The Kernel Hub allows Python libraries and applications to load compute
kernels directly from the [Hub](https://hf.co/). To support this kind
of dynamic loading, Hub kernels differ from traditional Python kernel
packages in that they are made to be:

- Portable: a kernel can be loaded from paths outside `PYTHONPATH`.
- Unique: multiple versions of the same kernel can be loaded in the
  same Python process.
- Compatible: kernels must support all recent versions of Python and
  the different PyTorch build configurations (various CUDA versions
  and C++ ABIs). Furthermore, older C library versions must be supported.

`kernel-builder` is a set of tools that can build conforming kernels. It
takes care of:

- Building kernels for all supported PyTorch configurations (C++98/11 and
  different CUDA versions).
- Compatibility with old glibc and libstdc++ versions, so that kernels also
  work on older Linux distributions.
- Registering Torch ops, such that multiple versions the same kernel can be
  loaded without namespace conflicts.

`kernel-builder` builds are configured through a `build.toml` file.
`build.toml` is a simple format that does not require intricate knowledge
of CMake or setuptools.

This page describes the directory layout of a kernel-builder project, the
format of the `build.toml` file, and some additional Python glue that
`kernel-builder` provides. We will use a [simple ReLU kernel](../examples/relu)
as the running example.

## Kernel project layout

Kernel projects follow this general directory layout:

```text
relu
├── build.toml
├── relu_kernel
│   └── relu.cu
└── torch-ext
    └── torch_bindings.cpp
    └── torch_bindings.h
    └── relu
        └── __init__.py
```

In this example we can find:

- The build configuration in `build.toml`.
- One or more top-level directories containing kernels (`relu_kernel`).
- The `torch-ext` directory, which contains:
  - `torch_bindings.h`: contains declarations for kernel entry points
    (from `kernel_a` and `kernel_b`).
  - `torch_bindings.cpp`: registers the entry points as Torch ops.
  - `torch_ext/relu`: contains any Python wrapping the kernel needs. At the
    bare minimum, it should contain an `__init__.py` file.

## `build.toml`

`build.toml` tells `kernel-builder` what to build and how. It looks as
follows for the `relu` kernel:

```toml
[general]
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
```

### `general`

`name` defines the name of the kernel. The Python code for a Torch extension
must be stored in `torch-ext/<name>`.

### `torch`

This section describes the Torch extension. In the future, there may be
similar sections for other frameworks. This section can contain the
following options:

- `src` (required): a list of source files and headers.
- `universal` (optional): set to `true` when the extension is a pure
  Python extension, such as a Triton kernel. Default: `false`.
- `pyext` (optional): the list of extensions for Python files. Default:
  `["py", "pyi"]`.
- `include` (optional): include directories relative to the project root.
  Default: `[]`.

### `kernel.<name>`

Specification of a kernel with the name `<name>`. This section can contain
the following options:

- `cuda-capabilities` (required): a list of CUDA capabilities that the
  kernel should be compiled for. The effective capabilities are the
  intersection of this list and the capabilities a given Torch version
  is compiled with.
- `rocm-archs` (required): a list of ROCm architectures that the kernel
  should be compiled for.
- `depends` (required): a list of dependencies. The supported dependencies
  are listed in [`deps.nix`](../lib/deps.nix].
- `src` (required): a list of source files and headers.
- `include` (optional): include directories relative to the project root.
  Default: `[]`.
- `language` (optional): the language used for the kernel. Must be `cuda`
  or `cuda-hipify`. `cuda-hipify` is for CUDA kernels that can also be
  compiled for ROCm using hipify. **Warning:** `cuda-hipify` is currently
  experimental and does not produce conforming kernels yet.
  Default: `"cuda"`

Multiple `kernel.<name>` sections can be defined in the same `build.toml`.
See for example [`kernels-community/quantization`](https://huggingface.co/kernels-community/quantization/)
for an example with multiple kernel sections.

## Torch bindings

### Defining bindings

Torch bindings are defined in C++, kernels commonly use two files:

- `torch_bindings.h` containing function declarations.
- `torch_bindings.cpp` registering the functions as Torch ops.

For instance, the `relu` kernel has the following declaration in
`torch_bindings.h`:

```cpp
#pragma once

#include <torch/torch.h>

void relu(torch::Tensor &out, torch::Tensor const &input);
```

This is a declaration for the actual kernel, which is in `relu_kernel/relu.cu`:

```cpp
#include <ATen/cuda/CUDAContext.h>
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
```

This function is then registered as a Torch op in `torch_bindings.cpp`:

```cpp
#include <torch/library.h>

#include "registration.h"
#include "torch_binding.h"

TORCH_LIBRARY_EXPAND(TORCH_EXTENSION_NAME, ops) {
  ops.def("relu(Tensor! out, Tensor input) -> ()");
  ops.impl("relu", torch::kCUDA, &relu);
}

REGISTER_EXTENSION(TORCH_EXTENSION_NAME)
```

This snippet uses macros from `registration.h` to register the function.
`registration.h` is generated by `kernel-builder` itself. A function
is registered through the `def`/`ops` methods. `ops` specifies the
function signature following the [function schema](https://github.com/pytorch/pytorch/blob/main/aten/src/ATen/native/README.md#func).
`impl` associates the function name with the C/C++ function and
the applicable device.

## Using kernel functions from Python

The bindings are typically wrapped in Python code in `torch_ext/<name>`.
The native code is exposed under the `torch.ops` namespace. However,
we add some unique material to the name of the extension to ensure that
different versions of the same extension can be loaded at the same time.
As a result, the extension is registered as
`torch.ops.<name>_<unique_material>`.

To deal with this uniqueness, `kernel_builder` generates a Python module
named `_ops` that contains an alias for the name. This can be used to
refer to the correct `torch.ops` module. For example:

```python
from typing import Optional
import torch
from ._ops import ops

def relu(x: torch.Tensor, out: Optional[torch.Tensor] = None) -> torch.Tensor:
    if out is None:
        out = torch.empty_like(x)
    ops.relu(out, x)
    return out
```
