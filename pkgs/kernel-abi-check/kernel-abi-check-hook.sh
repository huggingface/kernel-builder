#!/bin/sh

_checkAbiHook() {
  if [ -z "${abiVersion}" ]; then
    echo "Skipping ABI check"
  else
    echo "Checking of ${abiVersion} ABI compatibility"
    find $out/${extensionName} -name '*.so' \
      -exec kernel-abi-check ${abiVersion} {} \;
  fi
}

postInstallCheckHooks+=(_checkAbiHook)
