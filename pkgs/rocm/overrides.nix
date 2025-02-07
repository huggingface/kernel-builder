{
  lib,
}:
let
  applyOverrides =
    overrides: final: prev:
    lib.mapAttrs (name: value: prev.${name}.overrideAttrs (final.callPackage value { })) overrides;
in
applyOverrides {
  comgr =
    { zlib, zstd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        zlib
        zstd
      ];
    };

  hipblaslt =
    { hip-runtime-amd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ hip-runtime-amd ];
    };

  hipcc =
    { }:
    prevAttrs: {
      passthru = prevAttrs.passthru or { } // {
        gpuTargets = lib.forEach [
          "803"
          "900"
          "906"
          "908"
          "90a"
          "940"
          "941"
          "942"
          "1010"
          "1012"
          "1030"
          "1100"
          "1101"
          "1102"
        ] (target: "gfx${target}");
      };
    };

  hipify-clang =
    { zlib, zstd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        zlib
        zstd
      ];
    };

  openmp-extras-dev =
    { ncurses, zlib }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        ncurses
        zlib
      ];
    };

  openmp-extras-runtime =
    { rocm-llvm }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ rocm-llvm ];
      # Can we change rocm-llvm to pick these up?
      installPhase = (prevAttrs.installPhase or "") + ''
        addAutoPatchelfSearchPath ${rocm-llvm}/lib/llvm/lib
      '';
    };

  hsa-rocr =
    {
      elfutils,
      libdrm,
      numactl,
    }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        elfutils
        libdrm
        numactl
      ];
    };

  rocfft =
    { hip-runtime-amd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ hip-runtime-amd ];
    };

  rocm-llvm =
    { libxml2, zlib, zstd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        libxml2
        zlib
        zstd
      ];
    };

  rocminfo =
    { python3 }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ python3 ];
    };

  rocrand =
    { hip-runtime-amd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ hip-runtime-amd ];
    };

  roctracer =
    { comgr }:
    prevAttr: {
      buildInputs = prevAttr.buildInputs ++ [ comgr ];
    };
}
