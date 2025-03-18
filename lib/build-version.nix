{
  gpu,
  pkgs,
  torch,
}:
let
  inherit (pkgs) lib;
  flattenVersion = version: lib.replaceStrings [ "." ] [ "" ] (lib.versions.pad 2 version);
  abi = torch: if torch.passthru.cxx11Abi then "cxx11" else "cxx98";
  targetPlatform = pkgs.stdenv.targetPlatform.system;
  cudaVersion = torch: "cu${flattenVersion torch.cudaPackages.cudaMajorMinorVersion}";
  rocmVersion = torch: "rocm-${flattenVersion torch.rocmPackages.hipcc.version}";
  gpuVersion = torch: (if torch.cudaSupport then cudaVersion else rocmVersion) torch;
  torchVersion = torch: flattenVersion torch.version;
in
"torch${torchVersion torch}-${abi torch}-${gpuVersion torch}-${targetPlatform}"
