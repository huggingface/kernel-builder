#!/bin/sh

echo "Sourcing get-kernel-check-hook.sh"

_getKernelCheckHook() {
  if [ ! -z "${getKernelCheck}" ]; then
    echo "Checking loading kernel with get_kernel"
    echo "Check whether the kernel can be loaded with get-kernel: ${getKernelCheck}"

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
