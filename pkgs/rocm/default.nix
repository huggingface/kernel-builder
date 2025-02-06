{
  callPackage,
}:

let
  deps = builtins.fromJSON (builtins.readFile ./deps.json);
  packages = [
    "comgr"
    "hipblas"
    "hipcc"
    "hipfft"
    "hipify-clang"
    "hipsolver"
    "llvm"
    "miopen-hip"
    "openmp-extras-dev"
    "rccl"
    "rocm-core"
    "rocm-device-libs"
    "rocm-hip-runtime"
    "rocminfo"
    "rocrand"
    "rocblas"
    "rocfft"
    "rocsolver"
    "rocsparse"
    "roctracer"
    "hipcub-dev"
    "hipsparse"
    "rocthrust-dev"
    "rocprim-dev"
  ];
  rocmPackages' = builtins.listToAttrs (map (pname: {
    name = pname;
    value = callPackage ./generic.nix { inherit pname; };
  }) packages);
  rocmPackages = callPackage ./overrides.nix { rocmPackages = rocmPackages'; };
in
  rocmPackages // { clr = rocmPackages.hipcc; }
