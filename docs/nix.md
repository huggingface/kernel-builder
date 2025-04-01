# Using the kernel builder with Nix

The kernel builder uses Nix for building kernels. You can build or
run the kernels directly if you have [Nix installed](https://nixos.org/download/)
on your system. On systems without Nix you can use the [Docker](./docker.md)
image, which is a wrapper around Nix.

## Getting started

The easiest way get all the Nix functionality is by putting a
`flake.nix` in your kernel repository. To do so, copy
[`examples/relu/flake.nix`](../examples/relu/flake.nix) into the
same directory as your `build.toml` file. Then run `nix flake update`.
This generates a `flake.lock` file that pins the kernel builder
and _all_ its transitive dependencies. Commit both `flake.nix`
and `flake.lock` to your repository, this will ensure that kernel
builds are reproducible.

Since the kernel builder depends on many packages (e.g. every supported
PyTorch version), it is recommended to [enable the kernel-builder cache](https://app.cachix.org/cache/kernel-builder)
to avoid expensive rebuilds.

The kernel builder also provides Nix development shells with all Torch
and CUDA/ROCm dependencies needed to develop kernels (see below). If
you want to test your kernels inside a Nix development shell and you
are not using NixOS, [make sure that the CUDA driver is visible](https://danieldk.eu/Nix-CUDA-on-non-NixOS-systems#make-runopengl-driverlib-and-symlink-the-driver-library) to Torch.

## Building kernels with Nix

A kernel that has a `flake.nix` file can be built with `nix build`.
For example:

```bash
cd examples/activation
nix build .#bundle -L
```

You can put this `flake.nix` in your own kernel's root directory to
get add Nix support to your kernel.

## Shell for testing a kernel

You can also start a development shell. This will give you a Python interpreter
with the kernel in Python's search path. This makes it more convenient to run
tests:

```bash
cd examples/activation
nix develop -L
python -m pytest tests
```

## Building a kernel without `flake.nix`

If a kernels source directory does not have a `flake.nix` file, you can build the
kernel using the `buildTorchExtensionBundle` function from the kernel builder
itself:

```bash
cd examples/activation
nix build --impure --expr 'with import ../..; lib.x86_64-linux.buildTorchExtensionBundle ./.' -L
```
