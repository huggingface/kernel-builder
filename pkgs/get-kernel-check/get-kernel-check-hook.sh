#!/bin/sh

echo "Sourcing get-kernel-check-hook.sh"

_getKernelCheckHook() {
  if [ ! -z "${getKernelCheck}" ]; then
    echo "Checking loading kernel with get_kernel"
    echo "Check whether the kernel can be loaded with get-kernel: ${getKernelCheck}"

    # We strip the full library paths from the extension. Unfortunately,
    # in a Nix environment, the library dependencies cannot be found
    # anymore. So we have to add the Torch library directory to the
    # dynamic linker path to get it to pick it up.
    if [ $(uname -s) == "Darwin" ]; then
      TORCH_DIR=$(python -c "from pathlib import Path; import torch; print(Path(torch.__file__).parent)")
      export DYLD_LIBRARY_PATH="${TORCH_DIR}/lib:${DYLD_LIBRARY_PATH}"
    fi

    TMPDIR=$(mktemp -d -t test.XXXXXX) || exit 1
    trap "rm -rf '$TMPDIR'" EXIT

    # Emulate the bundle layout that kernels expects. This even works
    # for universal kernels, since kernels checks the non-universal
    # path first.
    BUILD_VARIANT=$(python -c "from kernels.utils import build_variant; print(build_variant())")
    mkdir -p "${TMPDIR}/build"
    ln -s "$out" "${TMPDIR}/build/${BUILD_VARIANT}"

    python -c "from pathlib import Path; import kernels; kernels.get_local_kernel(Path('${TMPDIR}'), '${getKernelCheck}')"
  fi
}

postInstallCheckHooks+=(_getKernelCheckHook)
