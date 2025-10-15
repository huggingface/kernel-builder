# kernel-builder

<div align="center">
<img src="https://github.com/user-attachments/assets/4b5175f3-1d60-455b-8664-43b2495ee1c3" width="450" height="450" alt="kernel-builder logo">
<p align="center">
    <a href="https://github.com/huggingface/kernel-builder/actions/workflows/docker-build-push.yaml"><img alt="Build and Push Docker Image" src="https://img.shields.io/github/actions/workflow/status/huggingface/kernel-builder/docker-build-push.yaml?label=docker"></a>
    <a href="https://github.com/huggingface/kernel-builder/tags"><img alt="GitHub tag" src="https://img.shields.io/github/v/tag/huggingface/kernel-builder"></a>
    <a href="https://github.com/huggingface/kernel-builder/pkgs/container/kernel-builder"><img alt="GitHub package" src="https://img.shields.io/badge/container-ghcr.io-blue"></a>
</p>
</div>
<hr/>

This repo contains a Nix package that can be used to build custom machine learning kernels for PyTorch. The kernels are built using the [PyTorch C++ Frontend](https://pytorch.org/cppdocs/frontend.html) and can be loaded from the Hub with the [kernels](https://github.com/huggingface/kernels)
Python package.

This builder is a core component of the larger kernel build/distribution system.

**Torch 2.9 note:** kernel-builder currently builds Torch 2.9 extensions based on
the [fifth release candidate](https://dev-discuss.pytorch.org/t/reminder-calls-for-features-upcoming-branch-cut/3225).
If you upload Torch 2.9 kernels, please validate them against
the final Torch 2.9.0 release. In the unlikely case of an ABI-breaking
change, you can rebuild and upload your kernel once kernel-builder
is updated for the final release

## 🚀 Quick Start

We recommend using [Nix](https://nixos.org/download.html) to build kernels. To speed up builds, first enable the Hugging Face binary cache:

```bash
# Install cachix and configure the cache
cachix use huggingface

# Or run once without installing cachix
nix run nixpkgs#cachix -- use huggingface
```

Then quick start a build with:

```bash
cd examples/activation
nix run .#build-and-copy \
  --max-jobs 2 \
  --cores 8 \
  -L
```

Where `--max-jobs` specifies the number of build variant that should be built concurrently and `--cores` the number of CPU cores that should be used per build variant.

The compiled kernel will then be available in the local `build/` directory.
We also provide Docker containers for CI builds. For a quick build:

```bash
# Using the prebuilt container
cd examples/activation
docker run --rm \
  --mount type=bind,source=$(pwd),target=/kernelcode \
  -w /kernelcode ghcr.io/huggingface/kernel-builder:main build
```

See [dockerfiles/README.md](./dockerfiles/README.md) for more options, including a user-level container for CI/CD environments.

## 🎯 Hardware Support

| Hardware   | Kernels Support | Kernel-Builder Support | Kernels Validated in CI | Tier |
| ---------- | --------------- | ---------------------- | ----------------------- | ---- |
| CUDA       | ✓               | ✓                      | ✓                       | 1    |
| ROCm       | ✓               | ✓                      | ✗                       | 2    |
| XPU        | ✓               | ✓                      | ✗                       | 2    |
| Metal      | ✓               | ✓                      | ✗                       | 2    |
| Huawei NPU | ✓               | ✗                      | ✗                       | 3    |

# 📚 Documentation

- [Writing Hub kernels](./docs/writing-kernels.md)
- [Building kernels with Nix](./docs/nix.md)
- [Building kernels with Docker](./docs/docker.md) (for systems without Nix)
- [Local kernel development](docs/local-dev.md) (IDE integration)
- [Kernel security](./docs/security.md)
- [Why Nix?](./docs/why-nix.md)

## Credits

The generated CMake build files are based on the vLLM build infrastructure.
