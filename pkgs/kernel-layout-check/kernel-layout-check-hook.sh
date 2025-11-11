#!/bin/sh

echo "Sourcing kernel-layout-check-hook.sh"

kernelLayoutCheckHook() {
  echo "Checking kernel layout"

  if [ -z ${extensionName+x} ]; then
    echo "extensionName must be set in derivation"
    exit 1
  fi

  if [ ! -f source/torch-ext/${extensionName}/__init__.py ]; then
    echo "Python module at source/torch-ext/${extensionName} must contain __init__.py"
    exit 1
  fi

  # TODO: remove once the old location is removed from kernels.
  if [ -e source/torch-ext/${extensionName}/${extensionName} ]; then
    echo "Python module at source/torch-ext/${extensionName} must not have ${extensionName} file or directory."
    exit 1
  fi
}

if [ -z "${dontCheckLayout-}" ]; then
  postUnpackHooks+=(kernelLayoutCheckHook)
fi
