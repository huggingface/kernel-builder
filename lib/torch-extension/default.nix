{
  extensionName,
  nvccThreads,
  rev,

  # Wheter to strip rpath for non-nix use.
  stripRPath ? false,

  src,

  config,
  cudaSupport ? config.cudaSupport,
  rocmSupport ? config.rocmSupport,

  lib,
  stdenv,
  cudaPackages,
  cmake,
  cmakeNvccThreadsHook,
  ninja,
  python3,
  build2cmake,
  rocmPackages,

  extraDeps ? [ ],
  torch,
}:

stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit nvccThreads src;

  # Generate build files.
  postPatch = ''
    build2cmake generate-torch --ops-id ${rev} build.toml
  '';

  # hipify copies files, but its target is run in the CMake build and install
  # phases. Since some of the files come from the Nix store, this fails the
  # second time around.
  preInstall = ''
    chmod -R u+w .
  '';

  nativeBuildInputs =
    [
      cmake
      ninja
      build2cmake
    ]
    ++ lib.optionals cudaSupport [
      cmakeNvccThreadsHook
      cudaPackages.cuda_nvcc
    ]
    ++ lib.optionals rocmSupport [
      rocmPackages.clr
    ];

  buildInputs =
    [
      torch
      torch.cxxdev
    ]
    ++ lib.optionals cudaSupport (
      with cudaPackages;
      [
        cuda_cudart

        # Make dependent on build configuration dependencies once
        # the Torch dependency is gone.
        cuda_cccl
        libcublas
        libcusolver
        libcusparse
      ]
    )
    #++ lib.optionals rocmSupport (with rocmPackages; [ clr rocm-core ])
    ++ extraDeps;

  env =
    lib.optionalAttrs cudaSupport {
      CUDAToolkit_ROOT = "${lib.getDev cudaPackages.cuda_nvcc}";
      TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" torch.cudaCapabilities;
    }
    // lib.optionalAttrs rocmSupport {
      PYTORCH_ROCM_ARCH = lib.concatStringsSep ";" torch.rocmArchs;
    };

  # If we use the default setup, CMAKE_CUDA_HOST_COMPILER gets set to nixpkgs g++.
  dontSetupCUDAToolkitCompilers = true;

  cmakeFlags =
    [
      (lib.cmakeFeature "Python_EXECUTABLE" "${python3.withPackages (ps: [ torch ])}/bin/python")
    ]
    ++ lib.optionals cudaSupport [
      (lib.cmakeFeature "CMAKE_CUDA_HOST_COMPILER" "${stdenv.cc}/bin/g++")
    ]
    ++ lib.optionals rocmSupport [
      (lib.cmakeFeature "CMAKE_HIP_COMPILER_ROCM_ROOT" "${rocmPackages.clr}")
    ];

  postInstall =
    ''
      (
        cd ..
        cp -r torch-ext/${extensionName} $out/
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
})
