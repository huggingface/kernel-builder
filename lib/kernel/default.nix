{
  kernelName,
  kernelSources,
  kernelDeps,
  kernelInclude,
  cudaCapabilities,
  src,

  lib,
  stdenv ? cudaPackages.backendStdenv,
  cudaPackages,
  cmake,
  ninja,
  cmakeNvccThreadsHook,

  nvccThreads,
}:

let
  dropDot = builtins.replaceStrings [ "." ] [ "" ];
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

  # If we use the default setup, CMAKE_CUDA_HOST_COMPILER gets set to nixpkgs g++.
  dontSetupCUDAToolkitCompilers = true;

  cmakeFlags = [
    (lib.cmakeFeature "KERNEL_NAME" kernelName)
    (lib.cmakeFeature "KERNEL_SOURCES" (lib.concatStringsSep ";" kernelSources))
    (lib.cmakeFeature "KERNEL_INCLUDE_DIRS" (lib.concatStringsSep ";" kernelInclude))
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" (dropDot (lib.concatStringsSep ";" cudaCapabilities)))
    (lib.cmakeFeature "CMAKE_CUDA_HOST_COMPILER" "${stdenv.cc}/bin/g++")
  ];
}
