## Building kernels with Nix

The kernel builder uses Nix for building kernels (the [Docker](./docker.md) image
a wrapper around Nix). You can also use Nix directly if you have Nix
installed on your system. The easiest way is to put a `flake.nix`
file in the kernel directory, such as in the examples included in the
`examples` directory:

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
