{
  extensionName,
  extensionVersion,
  extensionSources,
  pySources,

  # Wheter to strip rpath for non-nix use.
  stripRPath ? false,

  # Keys are kernel names, values derivations.
  kernels,

  src,

  lib,
  cudaPackages,
  cmake,
  ninja,

  # Remove, only here while we don't have a shim yet.
  torch,
}:

let
  flatVersion = lib.replaceStrings [ "." ] [ "_" ] (lib.versions.pad 3 extensionVersion);
  stdenv = cudaPackages.backendStdenv;
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
    # Remove after removing torch dependency.
    #TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" cudaCapabilities;
  };

  cmakeFlags =
    let
      kernelPath = name: drv: "${drv}/lib/lib${name}.a";
      kernelLibs = lib.mapAttrsToList kernelPath kernels;
    in
    [
      (lib.cmakeFeature "EXTENSION_NAME" "_${extensionName}_${flatVersion}")
      (lib.cmakeFeature "EXTENSION_DEST" extensionName)
      (lib.cmakeFeature "EXTENSION_SOURCES" (lib.concatStringsSep ";" extensionSources))
      (lib.cmakeFeature "KERNEL_LIBRARIES" (lib.concatStringsSep ";" kernelLibs))
    ];

  postInstall =
    let
      pySources' = map (src: ''"${src}"'') pySources;
    in
    ''
      (
        cd ..
        cp ${lib.concatStringsSep " " pySources'} $out/${extensionName}/
        substitute ${./_ops.py.in} $out/${extensionName}/_ops.py \
          --subst-var-by EXTENSION_NAME "${extensionName}_${flatVersion}"
      )
    ''
    + lib.optionalString stripRPath ''
      find $out/${extensionName} -name '*.so' \
        -exec patchelf --set-rpath "" {} \;
    '';

  passthru = {
    inherit torch;
  };
}
