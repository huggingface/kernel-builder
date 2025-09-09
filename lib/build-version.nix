{
  buildConfig,
  pkgs,
  torch,
  bundleBuild,
}:
let
  inherit (pkgs) lib;
  inherit (import ./version-utils.nix { inherit lib; }) flattenVersion abiString;
  abi = torch: abiString torch.passthru.cxx11Abi;
  targetPlatform = pkgs.stdenv.targetPlatform.system;
  cudaVersion = torch: "cu${flattenVersion torch.cudaPackages.cudaMajorMinorVersion}";
  rocmVersion =
    torch: "rocm${flattenVersion (lib.versions.majorMinor torch.rocmPackages.rocm.version)}";
  torchVersion = torch: flattenVersion torch.version;
  xpuVersion =
    torch:
    "xpu${flattenVersion (lib.versions.majorMinor torch.xpuPackages.intel-oneapi-dpcpp-cpp.version)}";
  gpuVersion =
    torch:
    if torch.cudaSupport then
      cudaVersion torch
    else if (torch ? rocmPackages) && (torch.rocmSupport or false) then
      rocmVersion torch
    else if (torch ? xpuPackages) && (torch.xpuSupport or false) then
      xpuVersion torch
    else
      null;
in
if pkgs.stdenv.hostPlatform.isDarwin then
  "torch${torchVersion torch}-metal-${targetPlatform}"
else if gpuVersion torch != null then
  "torch${torchVersion torch}-${abi torch}-${gpuVersion torch}-${targetPlatform}"
else
  throw "No supported GPU framework (CUDA, ROCm, XPU, Metal) detected for build-version.nix"
