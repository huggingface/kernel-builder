# Build variants

A kernel can be compliant for a specific compute framework (e.g. CUDA) or
architecture (e.g. x86_64). For compliance with a compute framework and
architecture combination, all the build variants listed below must be
available. This list will be updated as new PyTorch versions are released.

## Metal aarch64-darwin

- `torch27-cxx11-metal-aarch64-darwin`

## CUDA aarch64-linux

- `torch26-cxx11-cu126-aarch64-linux`
- `torch26-cxx98-cu126-aarch64-linux`
- `torch27-cxx11-cu126-aarch64-linux`
- `torch27-cxx11-cu128-aarch64-linux`

## CUDA x86_64-linux

- `torch26-cxx11-cu118-x86_64-linux`
- `torch26-cxx11-cu124-x86_64-linux`
- `torch26-cxx11-cu126-x86_64-linux`
- `torch26-cxx98-cu118-x86_64-linux`
- `torch26-cxx98-cu124-x86_64-linux`
- `torch26-cxx98-cu126-x86_64-linux`
- `torch27-cxx11-cu118-x86_64-linux`
- `torch27-cxx11-cu126-x86_64-linux`
- `torch27-cxx11-cu128-x86_64-linux`

## ROCm x86_64-linux

- `torch26-cxx11-rocm62-x86_64-linux`
- `torch27-cxx11-rocm63-x86_64-linux`

## Universal

Kernels that are in pure Python (e.g. Triton kernels) only need to provide
a single build variant:

- `torch-universal`
