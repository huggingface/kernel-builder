{
  kernelName,
  kernelSources,
  kernelDeps,
  kernelInclude,
  cudaCapabilities,
  src,

  lib,
  cudaPackages,
  cmake,
  ninja,

  nvccThreads ? 4,
}:

let
  dropDot = builtins.replaceStrings [ "." ] [ "" ];
  stdenv = cudaPackages.backendStdenv;
in
stdenv.mkDerivation {
  name = kernelName;

  inherit src;

  # Copy generic build files into the source tree.
  postPatch = ''
    cp ${./CMakeLists.txt} CMakeLists.txt
  '';

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = kernelDeps;

  env = {
    # Remove after removing torch dependency.
    TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" cudaCapabilities;
  };

  cmakeFlags = [
    (lib.cmakeFeature "KERNEL_NAME" kernelName)
    (lib.cmakeFeature "KERNEL_SOURCES" (lib.concatStringsSep ";" kernelSources))
    (lib.cmakeFeature "KERNEL_INCLUDE_DIRS" (lib.concatStringsSep ";" kernelInclude))
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" (dropDot (lib.concatStringsSep ";" cudaCapabilities)))
    (lib.cmakeFeature "NVCC_THREADS" (toString nvccThreads))
  ];

  preBuild = ''
    # Even when using nvcc threading, we should respect the bound.
    export NIX_BUILD_CORES=$(($NIX_BUILD_CORES / ${toString nvccThreads}))
  '';
}
