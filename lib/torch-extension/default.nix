{
  extensionName,
  extensionVersion,
  extensionSources,
  extensionInclude,

  # Wheter to strip rpath for non-nix use.
  stripRPath ? false,

  # Keys are kernel names, values derivations.
  kernels,

  src,
  pySrc,

  lib,
  stdenv ? cudaPackages.backendStdenv,
  cudaPackages,
  cmake,
  ninja,

  torch,
}:

let
  flatVersion = lib.replaceStrings [ "." ] [ "_" ] (lib.versions.pad 3 extensionVersion);
in
stdenv.mkDerivation {
  pname = "${extensionName}-torch-ext";
  version = extensionVersion;

  inherit src;

  # Copy generic build files into the source tree.
  postPatch = ''
    cp ${./CMakeLists.txt} CMakeLists.txt
  '';

  nativeBuildInputs = [
    cmake
    ninja
    cudaPackages.cuda_nvcc
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
    ++ (lib.attrValues kernels);

  env = {
    CUDAToolkit_ROOT = "${lib.getDev cudaPackages.cuda_nvcc}";
  };

  # If we use the default setup, CMAKE_CUDA_HOST_COMPILER gets set to nixpkgs g++.
  dontSetupCUDAToolkitCompilers = true;

  cmakeFlags =
    let
      kernelPath = name: drv: "${drv}/lib/lib${name}.a";
      kernelLibs = lib.mapAttrsToList kernelPath kernels;
    in
    [
      (lib.cmakeFeature "EXTENSION_NAME" "_${extensionName}_${flatVersion}")
      (lib.cmakeFeature "EXTENSION_DEST" extensionName)
      (lib.cmakeFeature "EXTENSION_SOURCES" (lib.concatStringsSep ";" extensionSources))
      (lib.cmakeFeature "EXTENSION_INCLUDE_DIRS" (lib.concatStringsSep ";" extensionInclude))
      (lib.cmakeFeature "KERNEL_LIBRARIES" (lib.concatStringsSep ";" kernelLibs))
      (lib.cmakeFeature "CMAKE_CUDA_HOST_COMPILER" "${stdenv.cc}/bin/g++")
    ];

  postInstall =
    ''
      (
        cd ..
        substitute ${./_ops.py.in} $out/${extensionName}/_ops.py \
          --subst-var-by EXTENSION_NAME "${extensionName}_${flatVersion}"
      )
      cp -r ${pySrc}/* $out/${extensionName}
    ''
    + lib.optionalString stripRPath ''
      find $out/${extensionName} -name '*.so' \
        -exec patchelf --set-rpath "" {} \;
    '';

  passthru = {
    inherit torch;
  };
}
