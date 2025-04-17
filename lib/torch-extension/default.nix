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
  kernel-abi-check,
  build2cmake,
  rocmPackages,

  extraDeps ? [ ],
  torch,

  doAbiCheck,
}:

let
  # CLR that uses the provided stdenv, which can be different from the default
  # to support old glibc/libstdc++ versions.
  clr = (
    rocmPackages.clr.override {
      clang = rocmPackages.llvm.clang.override {
        inherit stdenv;
        bintools = rocmPackages.llvm.bintools.override { libc = stdenv.cc.libc; };
        glibc = stdenv.cc.libc;
      };
    }
  );

in
stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit doAbiCheck nvccThreads src;

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
      kernel-abi-check
      cmake
      ninja
      build2cmake
    ]
    ++ lib.optionals cudaSupport [
      cmakeNvccThreadsHook
      cudaPackages.cuda_nvcc
    ]
    ++ lib.optionals rocmSupport [
      clr
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
      TORCH_CUDA_ARCH_LIST =
        if cudaPackages.cudaOlder "12.8" then
          "7.0;7.5;8.0;8.6;8.9;9.0+PTX"
        else
          "7.0;7.5;8.0;8.6;8.9;9.0;10.0;10.1;12.0+PTX";
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
      # Ensure sure that we use HIP from our CLR override and not HIP from
      # the symlink-joined ROCm toolkit.
      (lib.cmakeFeature "CMAKE_HIP_COMPILER_ROCM_ROOT" "${clr}")
      (lib.cmakeFeature "HIP_ROOT_DIR" "${clr}")
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

  doInstallCheck = true;

  passthru = {
    inherit torch;
  };
})
