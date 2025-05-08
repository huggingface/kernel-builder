# Using the kernel builder with Docker

<!-- toc -->
- [Using the kernel builder with Docker](#using-the-kernel-builder-with-docker)
  - [Quick Start](#quick-start)
  - [CLI Interface](#cli-interface)
    - [Examples](#examples)
  - [Configuration](#configuration)
    - [1. Environment Variables](#1-environment-variables)
    - [2. Command-line Options](#2-command-line-options)
  - [Development Shell](#development-shell)
    - [Persistent Development Environment](#persistent-development-environment)
  - [Final Output](#final-output)
  - [Reproducible run](#reproducible-run)
    - [Accessing kernel in expected format](#accessing-kernel-in-expected-format)
  - [Building from URL](#building-from-url)
  - [Development](#development)
<!-- tocstop -->

## Quick Start

We provide a Docker image with which you can build a kernel:

```bash
# navigate to the activation directory
cd examples/activation

# then run the following command to build the kernel
docker run --rm \
    -v $(pwd):/home/nixuser/kernelcode \
    ghcr.io/huggingface/kernel-builder:latest
```

This will build the kernel and save the output in the `build` directory in
the activation folder.

## CLI Interface

The kernel builder now includes a command-line interface for easier interaction. The following commands are available:

| Command       | Description                                                  |
| ------------- | ------------------------------------------------------------ |
| `build`       | Build the kernel extension (default if no command specified) |
| `dev`         | Start a development shell                                    |
| `fetch [URL]` | Clone and build from a Git URL                               |
| `help`        | Show help information                                        |

### Examples

```bash
# Build the kernel (same as the Quick Start example)
docker run --rm -v $(pwd):/home/nixuser/kernelcode ghcr.io/huggingface/kernel-builder:latest build

# Start an ephemeral development shell
docker run --rm -it -v $(pwd):/home/nixuser/kernelcode ghcr.io/huggingface/kernel-builder:latest dev

# Build from a Git URL
docker run --rm ghcr.io/huggingface/kernel-builder:latest fetch https://huggingface.co/kernels-community/activation.git

# Show help information
docker run --rm ghcr.io/huggingface/kernel-builder:latest help
```

## Configuration

The kernel builder can be configured in two ways:

### 1. Environment Variables

| Variable   | Description                                                         | Default |
| ---------- | ------------------------------------------------------------------- | ------- |
| `MAX_JOBS` | The maximum number of parallel jobs to run during the build process | `4`     |
| `CORES`    | The number of cores to use during the build process                 | `4`     |

```bash
docker run --rm \
    -v $(pwd):/home/nixuser/kernelcode \
    -e MAX_JOBS=8 \
    -e CORES=8 \
    ghcr.io/huggingface/kernel-builder:latest
```

### 2. Command-line Options

You can also specify these parameters using command-line options:

| Option        | Description                         | Default |
| ------------- | ----------------------------------- | ------- |
| `--jobs, -j`  | Set maximum number of parallel jobs | `4`     |
| `--cores, -c` | Set number of cores per job         | `4`     |

```bash
docker run --rm \
    -v $(pwd):/home/nixuser/kernelcode \
    ghcr.io/huggingface/kernel-builder:latest build --jobs 8 --cores 4
```

## Development Shell

For development purposes, you can start an interactive shell with:

```bash
docker run -it \
  --name my-dev-env \
  -v "$(pwd)":/home/nixuser/kernelcode \
  ghcr.io/huggingface/kernel-builder:latest dev
```

This will drop you into a Nix development shell with all the necessary tools installed.

### Persistent Development Environment

For iterative development, you can create a persistent container to maintain the Nix store cache across sessions:

```bash
# Create a persistent container and start a development shell
docker run -it \
  --name my-persistent-dev-env \
  -v "$(pwd)":/home/nixuser/kernelcode \
  ghcr.io/huggingface/kernel-builder:latest dev
```

You can restart and attach to this container in subsequent sessions without losing the Nix store cache or the kernel build:

```bash
# Start the container in detached mode
docker start my-persistent-dev-env

# Attach to the container
docker exec -it my-persistent-dev-env sh

# Once inside, start the development shell
/etc/kernelcode/cli.sh dev
```

This approach preserves the Nix store cache between sessions, making subsequent builds much faster.

## Final Output

The whole goal of building these kernels is to allow researchers, developers, and programmers to use high performance kernels in their code PyTorch code. Kernels uploaded to Hugging Face Hub can be loaded using the [kernels](https://github.com/huggingface/kernels/) package.

To load a kernel locally, you can should add the kernel build that is compatible with the Torch and CUDA versions in you environment to `PYTHONPATH`. For example:

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
activation.silu_and_mul(out, x)

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
    -v $(pwd):/home/nixuser/kernelcode \
    ghcr.io/huggingface/kernel-builder:latest
# we should now have the built kernels on our host
ls result
# torch24-cxx11-cu118-x86_64-linux  torch24-cxx98-cu121-x86_64-linux  torch25-cxx11-cu124-x86_64-linux
# torch24-cxx11-cu121-x86_64-linux  torch24-cxx98-cu124-x86_64-linux  torch25-cxx98-cu118-x86_64-linux
# torch24-cxx11-cu124-x86_64-linux  torch25-cxx11-cu118-x86_64-linux  torch25-cxx98-cu121-x86_64-linux
# torch24-cxx98-cu118-x86_64-linux  torch25-cxx11-cu121-x86_64-linux  torch25-cxx98-cu124-x86_64-linux
```

## Building from URL

You can also directly build kernels from a Git repository URL:

```bash
docker run --rm ghcr.io/huggingface/kernel-builder:latest fetch https://huggingface.co/kernels-community/activation.git
```

This will clone the repository into the container, build the kernels, and save the output in the container's `/kernelcode/build` directory. You can mount a volume to access the results:

```bash
docker run --rm \
    -v /path/to/output:/home/nixuser/kernelcode/build \
    ghcr.io/huggingface/kernel-builder:latest fetch https://huggingface.co/kernels-community/activation.git
```

## Development

The Docker image can be built locally when making changes to the kernel builder
using the provided [Dockerfile](../Dockerfile):

```bash
docker build -t ghcr.io/huggingface/kernel-builder:latest .

# You can build a kernel using this development container:
cd examples/activation
docker run --rm -v $(pwd):/home/nixuser/kernelcode ghcr.io/huggingface/kernel-builder:latest

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
