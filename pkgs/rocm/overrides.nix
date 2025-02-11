let
  applyOverrides =
    overrides: final: prev:
    prev.lib.mapAttrs (name: value: prev.${name}.overrideAttrs (final.callPackage value { })) overrides;
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

  hipblas =
    { hipblas-common-dev }:
    prevAttrs: {
      propagatedBuildInputs = prevAttrs.buildInputs ++ [ hipblas-common-dev ];
    };

  hipblaslt =
    { hip-runtime-amd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [ hip-runtime-amd ];
    };

  hipify-clang =
    { zlib, zstd }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        zlib
        zstd
      ];
    };

  hiprand =
    { hip-runtime-amd, rocrand }:
    prevAttrs: {
      buildInputs = prevAttrs.buildInputs ++ [
        hip-runtime-amd
        rocrand
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
      installPhase =
        (prevAttrs.installPhase or "")
        + ''
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
    {
      libxml2,
      zlib,
      zstd,
    }:
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
