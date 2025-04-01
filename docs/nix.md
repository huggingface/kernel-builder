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

## Shell for local development

`kernel-builder` provides shells for developing kernels. In such a shell,
all required dependencies are available, as well as `build2cmake` for generating
project files. For example:

```bash
$ nix develop
$ build2cmake generate-torch build.toml
$ cmake -B build-ext
$ cmake --build build-ext
```

If you want to test the kernel as a Python package, you can make a virtual
environment inside the shell:

```bash
$ nix develop
$ build2cmake generate-torch build.toml
$ python -m venv .venv
$ source .venv/bin/activate
$ pip install --no-build-isolation -e .
```

Development shells are available for every build configuration. For
instance, you can get a Torch 2.6 development shell for ROCm extensions
using:

```bash
$ nix develop .#devShells.torch26-cxx11-rocm62-x86_64-linux
```

## Shell for testing a kernel

You can also start a development shell. This will give you a Python interpreter
with the kernel in Python's search path. This makes it more convenient to run
tests:

```bash
cd examples/activation
nix develop -L .#test
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
