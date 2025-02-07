{
  lib,
  callPackage,
  rocmPackages,
}:
let
  applyOverrides =
    overrides:
    let
      rocmPackages' = lib.mapAttrs (
        name: value: rocmPackages.${name}.overrideAttrs (callPackage value { })
      ) overrides;
    in
    rocmPackages // rocmPackages';
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
    { }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ rocmPackages.hip-runtime-amd ];
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

  rocrand =
    { }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ rocmPackages.hip-runtime-amd ];
    };

  roctracer =
    { }:
    prevAttr: {
      buildInputs = prevAttr.buildInputs ++ [ rocmPackages.comgr ];
    };
}
