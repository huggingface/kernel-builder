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
  cmakeNvccThreadsHook,

  nvccThreads,
}:

let
  dropDot = builtins.replaceStrings [ "." ] [ "" ];
  stdenv = cudaPackages.backendStdenv;
in
stdenv.mkDerivation {
  inherit nvccThreads;

  name = kernelName;

  inherit src;

  # Copy generic build files into the source tree.
  postPatch = ''
    cp ${./CMakeLists.txt} CMakeLists.txt
  '';

  nativeBuildInputs = [
    cmake
    ninja
    cmakeNvccThreadsHook
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
  ];
}
