# Build variants

A kernel can be compliant for a specific compute framework (e.g. CUDA) or
architecture (e.g. x86_64). For compliance with a compute framework and
architecture combination, all the build variants listed below must be
available. This list will be updated as new PyTorch versions are released.

## CPU aarch64-darwin

- `torch28-cpu-aarch64-darwin`
- `torch29-cpu-aarch64-darwin`

## Metal aarch64-darwin

- `torch28-metal-aarch64-darwin`
- `torch29-metal-aarch64-darwin`

## CPU aarch64-linux

- `torch28-cxx11-cpu-aarch64-linux`
- `torch29-cxx11-cpu-aarch64-linux`

## CUDA aarch64-linux

- `torch28-cxx11-cu129-aarch64-linux`
- `torch29-cxx11-cu126-aarch64-linux`
- `torch29-cxx11-cu128-aarch64-linux`
- `torch29-cxx11-cu130-aarch64-linux`

## CPU x86_64-linux

- `torch28-cxx11-cpu-x86_64-linux`
- `torch29-cxx11-cpu-x86_64-linux`

## CUDA x86_64-linux

- `torch28-cxx11-cu126-x86_64-linux`
- `torch28-cxx11-cu128-x86_64-linux`
- `torch28-cxx11-cu129-x86_64-linux`
- `torch29-cxx11-cu126-x86_64-linux`
- `torch29-cxx11-cu128-x86_64-linux`
- `torch29-cxx11-cu130-x86_64-linux`

## ROCm x86_64-linux

- `torch28-cxx11-rocm63-x86_64-linux`
- `torch28-cxx11-rocm64-x86_64-linux`
- `torch29-cxx11-rocm63-x86_64-linux`
- `torch29-cxx11-rocm64-x86_64-linux`

## XPU x86_64-linux

- `torch28-cxx11-xpu20251-x86_64-linux`
- `torch29-cxx11-xpu20252-x86_64-linux`

## Universal

Kernels that are in pure Python (e.g. Triton kernels) only need to provide
a single build variant:

- `torch-universal`
