# kernel-builder

This repo contains a Nix package that can be used to build custom machine learning kernels for PyTorch. The kernels are built using the [PyTorch C++ Frontend](https://pytorch.org/cppdocs/frontend.html) and can be loaded by importing the corresponding Python module.

This builder is a core component of the larger kernel build/distribution system.

## Quick Start

We provide a Docker image with which you can build a kernel:

```bash
# navigate to the activation directory
cd examples/activation

# then run the following command to build the kernel
docker run --rm \
    -v $(pwd):/kernelcode \
    ghcr.io/huggingface/kernel-builder:latest

# this will build the kernel and save the output in the `build` directory in the activation folder
```

### Docker Arguments

The kernel builder can be configured using the following arguments:

| Argument   | Description                                                         | Default |
| ---------- | ------------------------------------------------------------------- | ------- |
| `MAX_JOBS` | The maximum number of parallel jobs to run during the build process | `4`     |
| `CORES`    | The number of cores to use during the build process                 | `4`     |

```bash
docker run --rm \
    -v $(pwd):/kernelcode \
    -e MAX_JOBS=8 \
    -e CORES=8 \
    ghcr.io/huggingface/kernel-builder:latest
```

## Final Output

The whole goal of building these kernels is to allow researchers, developers, and programmers to use high performance kernels in their code PyTorch code. Kernels uploaded to Hugging Face Hub can be loaded using the [hf-kernels](https://github.com/huggingface/hf-kernels/) package.

To load a kernel locally, you can should add the kernel build that is compatible with the Torch and CUDA versions in you environment to `PYTHON_PATH`. For example:

```bash
# PyTorch 2.4 and CUDA 12.1.
export PYTHONPATH="result/torch24-cxx98-cu121-x86_64-linux"
```

The kernel can then be imported as a Python module:

```python
import torch

import activation

x = torch.randn(10, 10)
out = torch.empty_like(x)
torch.ops.activation.silu_and_mul(out, x)

print(out)
```

## Reproducible run

### Accessing kernel in expected format

Kernels will be available in the [kernel-community](https://huggingface.co/kernels-community) on huggingface.co.

We can reproduce a build of a kernel by cloning the kernel repository and running the build command.

```bash
git clone git@hf.co:kernels-community/activation
cd activation
# then run the build command
docker run --rm \
    -v $(pwd):/kernelcode \
    ghcr.io/huggingface/kernel-builder:latest
# we should now have the built kernels on our host
ls result
# torch24-cxx11-cu118-x86_64-linux  torch24-cxx98-cu121-x86_64-linux  torch25-cxx11-cu124-x86_64-linux
# torch24-cxx11-cu121-x86_64-linux  torch24-cxx98-cu124-x86_64-linux  torch25-cxx98-cu118-x86_64-linux
# torch24-cxx11-cu124-x86_64-linux  torch25-cxx11-cu118-x86_64-linux  torch25-cxx98-cu121-x86_64-linux
# torch24-cxx98-cu118-x86_64-linux  torch25-cxx11-cu121-x86_64-linux  torch25-cxx98-cu124-x86_64-linux
```

## Nix

The Docker image uses [Nix](https://nixos.org) for building kernels. You can also use Nix directly if you have Nix installed on your system. The easiest way is to put a `flake.nix` file in the kernel directory, such as in the examples included in the `examples` directory:

```bash
cd examples/activation
nix build .#bundle -L
```

You can also start a development shell. This will give you a Python interpreter with the kernel in Python's path. This makes it more convenient to run tests:

```bash
cd examples/activation
nix develop -L
pytest tests
```

If a kernels source directory does not have a `flake.nix` file, you can build the kernel using the `buildTorchExtensionBundle` function from the kernel builder itself:

```bash
cd examples/activation
nix build --impure --expr 'with import ../..; lib.x86_64-linux.buildTorchExtensionBundle ./.' -L
```

## Development Notes

### Docker

Additionally we provide a [Dockerfile](./Dockerfile) that relieve you from the need to install Nix on your machine and enable you to build the kernel using a docker container.

```bash
# ../
# ├── activation
# └── kernel-builder
cd kernel-builder
docker build -t kernel-builder:dev .

# you can also build the kernel using a docker container
cd examples/activation
docker run --rm -v $(pwd):/kernelcode kernel-builder:dev

# copying path '/nix/store/1b79df96k9npmrdgwcljfh3v36f7vazb-source' from 'https://cache.nixos.org'...
# trace: evaluation warning: CUDA versions older than 12.0 will be removed in Nixpkgs 25.05; see the 24.11 release notes for more information
# ...
# copying path '/nix/store/1b79df96k9npmrdgwcljfh3v36f7vazb-source' from 'https://cache.nixos.org'...
ls result
# torch24-cxx11-cu118-x86_64-linux  torch24-cxx98-cu121-x86_64-linux  torch25-cxx11-cu124-x86_64-linux
# torch24-cxx11-cu121-x86_64-linux  torch24-cxx98-cu124-x86_64-linux  torch25-cxx98-cu118-x86_64-linux
# torch24-cxx11-cu124-x86_64-linux  torch25-cxx11-cu118-x86_64-linux  torch25-cxx98-cu121-x86_64-linux
# torch24-cxx98-cu118-x86_64-linux  torch25-cxx11-cu121-x86_64-linux  torch25-cxx98-cu124-x86_64-linux
```

## Credits

The generated CMake build files are based on the vLLM build infrastructure.
