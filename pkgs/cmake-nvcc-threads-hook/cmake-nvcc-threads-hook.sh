#!/bin/sh

_setNvccThreadsHook() {
  if [ -z "${nvccThreads}" ] || [ "${nvccThreads}" -ne "${nvccThreads}" ] 2>/dev/null; then
    # Detect number of available cores and use a reasonable fraction
    available_cores=$NIX_BUILD_CORES
    # Use 4 threads by default, but scale up to half the available cores on larger machines
    nvccThreads=$(( available_cores / 2 > 4 ? available_cores / 2 : 4 ))
    >&2 echo "Number of nvcc threads is not set, using ${nvccThreads} (from ${available_cores} available cores)"
  fi

  # Ensure that we do not use more threads than build cores.
  nvccThreads=$((NIX_BUILD_CORES < nvccThreads ? NIX_BUILD_CORES : nvccThreads ))

  # Change the number of build cores so that build cores * threads is
  # within bounds.
  # Use at least 2 build cores to maintain some parallelism
  export NIX_BUILD_CORES=$((NIX_BUILD_CORES / nvccThreads < 2 ? 2 : NIX_BUILD_CORES / nvccThreads))

  appendToVar cmakeFlags -DNVCC_THREADS="${nvccThreads}"
}

preConfigureHooks+=(_setNvccThreadsHook)
