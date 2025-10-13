{
  rocmSupport ? torch.rocmSupport,
  xpuSupport ? torch.xpuSupport,

  lib,
  callPackage,
  stdenv,
  stdenvGlibc_2_27,
  rocmPackages,
  writeScriptBin,
  xpuPackages,

  torch,
}:

let
  effectiveStdenv = if stdenv.hostPlatform.isLinux then stdenvGlibc_2_27 else stdenv;

  # CLR that uses the provided stdenv, which can be different from the default
  # to support old glibc/libstdc++ versions.
  clr = (
    rocmPackages.clr.override {
      clang = rocmPackages.llvm.clang.override {
        stdenv = effectiveStdenv;
        bintools = rocmPackages.llvm.bintools.override { libc = effectiveStdenv.cc.libc; };
        glibc = effectiveStdenv.cc.libc;
      };
    }
  );

  oneapi-torch-dev = xpuPackages.oneapi-torch-dev.override { stdenv = effectiveStdenv; };
  onednn-xpu = xpuPackages.onednn-xpu.override {
    inherit oneapi-torch-dev;
    stdenv = effectiveStdenv;
  };
in
{
  extraBuildDeps =
    lib.optionals xpuSupport [
      oneapi-torch-dev
      onednn-xpu
    ]
    ++ lib.optionals rocmSupport [ clr ];

  mkExtension = callPackage ./arch.nix {
    inherit
      clr
      oneapi-torch-dev
      onednn-xpu
      torch
      ;
    stdenv = effectiveStdenv;
  };

  mkNoArchExtension = callPackage ./no-arch.nix { inherit torch; };

  stdenv = effectiveStdenv;
}
