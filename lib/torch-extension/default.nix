{
  extensionName,
  extensionVersion,
  nvccThreads,
  pyRoot,

  # Wheter to strip rpath for non-nix use.
  stripRPath ? false,

  src,

  lib,
  stdenv ? cudaPackages.backendStdenv,
  cudaPackages,
  cmake,
  cmakeNvccThreadsHook,
  ninja,
  python3,
  toml2cmake,

  extraDeps ? [ ],
  torch,
}:

stdenv.mkDerivation {
  pname = "${extensionName}-torch-ext";
  version = extensionVersion;

  inherit nvccThreads src;

  # Generate build files.
  postPatch = ''
    toml2cmake generate-torch build.toml
  '';

  nativeBuildInputs = [
    cmake
    cmakeNvccThreadsHook
    ninja
    cudaPackages.cuda_nvcc
    toml2cmake
  ];

  buildInputs =
    [
      torch
      torch.cxxdev
    ]
    ++ (with cudaPackages; [
      cuda_cudart

      # Make dependent on build configuration dependencies once
      # the Torch dependency is gone.
      cuda_cccl
      libcublas
      libcusolver
      libcusparse
    ])
    ++ extraDeps;

  env = {
    CUDAToolkit_ROOT = "${lib.getDev cudaPackages.cuda_nvcc}";
    TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" torch.cudaCapabilities;
  };

  # If we use the default setup, CMAKE_CUDA_HOST_COMPILER gets set to nixpkgs g++.
  dontSetupCUDAToolkitCompilers = true;

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_CUDA_HOST_COMPILER" "${stdenv.cc}/bin/g++")
    (lib.cmakeFeature "Python_EXECUTABLE" "${python3.withPackages (ps: [ torch ])}/bin/python")
  ];

  postInstall =
    ''
      (
        cd ..
        cp -r ${pyRoot}/${extensionName} $out/
      )
      cp $out/_${extensionName}_*/* $out/${extensionName}
      rm -rf $out/_${extensionName}_*
    ''
    + lib.optionalString stripRPath ''
      find $out/${extensionName} -name '*.so' \
        -exec patchelf --set-rpath "" {} \;
    '';

  passthru = {
    inherit torch;
  };
}
