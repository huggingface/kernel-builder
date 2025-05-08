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

**Torch 2.7 note:** kernel-builder currently builds Torch 2.7 extensions based on
the [final release candidate](https://dev-discuss.pytorch.org/t/pytorch-release-2-7-0-final-rc-is-available/2898).
If you upload kernels Torch 2.7 kernels, please validate them against
the final Torch 2.7.0 release. In the unlikely case of an ABI-breaking
change, you can rebuild and upload a your kernel once kernel-builder
is updated for the final release.

## 🚀 Quick Start

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

# 📚 Documentation

- [Writing Hub kernels](./docs/writing-kernels.md)
- [Building kernels with Docker](./docs/docker.md)
- [Building kernels with Nix](./docs/nix.md)
- [Local kernel development](docs/local-dev.md) (IDE integration)
- [Why Nix?](./docs/why-nix.md)

## Credits

The generated CMake build files are based on the vLLM build infrastructure.
