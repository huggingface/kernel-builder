#!/bin/sh

_checkAbiHook() {
  if [ -z "${doAbiCheck:-}" ]; then
    echo "Skipping ABI check"
  else
    echo "Checking of ABI compatibility"
    find $out/${extensionName} -name '*.so' \
      -exec kernel-abi-check {} \;
  fi
}

postInstallCheckHooks+=(_checkAbiHook)
