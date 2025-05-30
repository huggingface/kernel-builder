{
  gpu,
  pkgs,
  torch,
  upstreamVariant,
}:
let
  inherit (pkgs) lib;
  inherit (import ./version-utils.nix { inherit lib; }) flattenVersion abiString;
  abi = torch: abiString torch.passthru.cxx11Abi;
  targetPlatform = pkgs.stdenv.targetPlatform.system;
  cudaVersion = torch: "cu${flattenVersion torch.cudaPackages.cudaMajorMinorVersion}";
  rocmVersion =
    torch: "rocm${flattenVersion (lib.versions.majorMinor torch.rocmPackages.rocm.version)}";
  gpuVersion = torch: (if torch.cudaSupport then cudaVersion else rocmVersion) torch;
  torchVersion = torch: flattenVersion torch.version;
in
if pkgs.stdenv.hostPlatform.isDarwin then
  "torch${torchVersion torch}-metal-${targetPlatform}"
else
  "torch${torchVersion torch}-${abi torch}-${gpuVersion torch}-${targetPlatform}"
