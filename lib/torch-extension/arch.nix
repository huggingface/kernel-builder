{
  cudaSupport ? torch.cudaSupport,
  rocmSupport ? torch.rocmSupport,
  xpuSupport ? torch.xpuSupport,

  lib,
  stdenv,

  # Native build inputs
  build2cmake,
  cmake,
  cmakeNvccThreadsHook,
  get-kernel-check,
  kernel-abi-check,
  ninja,
  python3,
  remove-bytecode-hook,
  rewrite-nix-paths-macho,
  writeScriptBin,

  # Framework packages
  cudaPackages,
  rocmPackages,
  xpuPackages,

  # Build inputs
  apple-sdk_15,
  metal-cpp,
  clr,
  oneapi-torch-dev,
  onednn-xpu,
  torch,
}:

{
  buildConfig,

  # Whether to do ABI checks.
  doAbiCheck ? true,

  # Whether to run get-kernel-check.
  doGetKernelCheck ? true,

  extensionName,

  # Extra dependencies (such as CUTLASS).
  extraDeps ? [ ],

  nvccThreads,

  # Wheter to strip rpath for non-nix use.
  stripRPath ? false,

  # Revision to bake into the ops name.
  rev,

  src,
}:

# Extra validation - the environment should correspind to the build config.
assert (buildConfig ? cudaVersion) -> cudaSupport;
assert (buildConfig ? rocmVersion) -> rocmSupport;
assert (buildConfig ? xpuVersion) -> xpuSupport;
assert (buildConfig.metal or false) -> stdenv.hostPlatform.isDarwin;

let
  # On Darwin, we need the host's xcrun for `xcrun metal` to compile Metal shaders.
  # It's not supported by the nixpkgs shim.
  xcrunHost = writeScriptBin "xcrunHost" ''
    echo "Calling command: $*"

    # Check if we are invoking metallib or metal
    if [[ "$*" =~ "metallib" ]]; then

      # If metallib is requested, find the air-lld from the Metal toolchain
      METALLIB_BIN=$(ls /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain*/Metal.xctoolchain/usr/bin/air-lld 2>/dev/null | head -n 1)
      if [ -z "$METALLIB_BIN" ]; then
        echo "Error: metallib (air-lld) not found" >&2
        exit 1
      fi

      # Remove the '-sdk macosx metallib' and other unsupported flags from the command arguments
      ARGS=$(echo "$@" | sed 's/-sdk macosx metallib //' | sed 's/-mmacosx-version-min=[^ ]* //')
      # Add platform version for macOS 15+ to support Metal 3.2 / AIR 2.7
      $METALLIB_BIN -platform_version macos 15.0 15.0 $ARGS

    elif [[ "$*" =~ "metal" ]]; then

      # If metal is requested, find the metal compiler from the Metal toolchain
      METAL_BIN=$(ls /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain*/Metal.xctoolchain/usr/bin/metal 2>/dev/null | head -n 1)
      if [ -z "$METAL_BIN" ]; then
        echo "Error: Metal compiler not found" >&2
        exit 1
      fi

      # Remove the '-sdk macosx metal' from the command arguments
      ARGS=$(echo "$@" | sed 's/-sdk macosx metal //')
      $METAL_BIN $ARGS
    else
      # In all other cases, just use the host xcrun
      unset DEVELOPER_DIR
      /usr/bin/xcrun $@
    fi
  '';

  metalSupport = buildConfig.metal or false;

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
      else if xpuSupport then
        "xpu"
      else if metalSupport then
        "metal"
      else
        "cpu"
    } --ops-id ${rev} build.toml
  '';

  # hipify copies files, but its target is run in the CMake build and install
  # phases. Since some of the files come from the Nix store, this fails the
  # second time around.
  preInstall = ''
    chmod -R u+w .
  '';

  nativeBuildInputs = [
    kernel-abi-check
    cmake
    ninja
    build2cmake
    remove-bytecode-hook
  ]
  ++ lib.optionals doGetKernelCheck [
    get-kernel-check
  ]
  ++ lib.optionals cudaSupport [
    cmakeNvccThreadsHook
    cudaPackages.cuda_nvcc
  ]
  ++ lib.optionals rocmSupport [
    clr
  ]
  ++ lib.optionals xpuSupport ([
    xpuPackages.ocloc
    oneapi-torch-dev
  ])
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    rewrite-nix-paths-macho
  ];

  buildInputs = [
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
  ++ lib.optionals rocmSupport (
    with rocmPackages;
    [
      hipcub-devel
      hipsparselt
      rocprim-devel
      rocthrust-devel
      rocwmma-devel
    ]
  )
  ++ lib.optionals xpuSupport ([
    oneapi-torch-dev
    onednn-xpu
  ])
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
  ]
  ++ extraDeps;

  env =
    lib.optionalAttrs cudaSupport {
      CUDAToolkit_ROOT = "${lib.getDev cudaPackages.cuda_nvcc}";
      TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" torch.cudaCapabilities;
    }
    // lib.optionalAttrs rocmSupport {
      PYTORCH_ROCM_ARCH = lib.concatStringsSep ";" torch.rocmArchs;
    }
    // lib.optionalAttrs xpuSupport {
      MKLROOT = oneapi-torch-dev;
      SYCL_ROOT = oneapi-torch-dev;
    };

  # If we use the default setup, CMAKE_CUDA_HOST_COMPILER gets set to nixpkgs g++.
  dontSetupCUDAToolkitCompilers = true;

  cmakeFlags = [
    (lib.cmakeFeature "Python_EXECUTABLE" "${python3.withPackages (ps: [ torch ])}/bin/python")
    # Fix: file RPATH_CHANGE could not write new RPATH, we are rewriting
    # rpaths anyway.
    (lib.cmakeBool "CMAKE_SKIP_RPATH" true)
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
  ++ lib.optionals metalSupport [
    # Use host compiler for Metal. Not included in the redistributable SDK.
    (lib.cmakeFeature "METAL_COMPILER" "${xcrunHost}/bin/xcrunHost")
  ];

  postInstall = ''
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

  getKernelCheck = extensionName;

  # We need access to the host system on Darwin for the Metal compiler.
  __noChroot = metalSupport;

  passthru = {
    inherit torch;
  };
})
