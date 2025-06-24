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
  build2cmake,
  kernel-abi-check,
  python3,
  rewrite-nix-paths-macho,
  rocmPackages,
  writeScriptBin,

  apple-sdk_15,
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

  # On Darwin, we need the host's xcrun for `xcrun metal` to compile Metal shaders.
  # t's not supported by the nixpkgs shim.
  xcrunHost = writeScriptBin "xcrunHost" ''
    # Use system SDK for Metal files.
    unset DEVELOPER_DIR
    /usr/bin/xcrun $@
  '';

in
stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit doAbiCheck nvccThreads src;

  # Generate build files.
  postPatch = ''
    build2cmake generate-torch --backend ${
      if cudaSupport then
        "cuda"
      else if rocmSupport then
        "rocm"
      else
        "metal"
    } --ops-id ${rev} build.toml
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
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      rewrite-nix-paths-macho
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
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      apple-sdk_15
    ]
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
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      # Use host compiler for Metal. Not included in the redistributable SDK.
      (lib.cmakeFeature "METAL_COMPILER" "${xcrunHost}/bin/xcrunHost")
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
    + (lib.optionalString (stripRPath && stdenv.hostPlatform.isLinux)) ''
      find $out/${extensionName} -name '*.so' \
        -exec patchelf --set-rpath "" {} \;
    ''
    + (lib.optionalString (stripRPath && stdenv.hostPlatform.isDarwin)) ''
      find $out/${extensionName} -name '*.so' \
        -exec rewrite-nix-paths-macho {} \;

      # Stub some rpath.
      find $out/${extensionName} -name '*.so' \
        -exec install_name_tool -add_rpath "@loader_path/lib" {} \;
    '';

  doInstallCheck = true;

  # We need access to the host system on Darwin for the Metal compiler.
  __noChroot = stdenv.hostPlatform.isDarwin;

  passthru = {
    inherit torch;
  };
})
