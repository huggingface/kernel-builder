{ lib }:
let
  inherit (import ./torch-version-utils.nix { inherit lib; })
    flattenSystems
    isCuda
    isMetal
    isRocm
    isXpu
    ;
in
rec {
  computeFramework =
    buildConfig:
    if buildConfig ? cudaVersion then
      "cuda"
    else if buildConfig ? metal then
      "metal"
    else if buildConfig ? "rocmVersion" then
      "rocm"
    else if buildConfig ? xpuVersion then
      "xpu"
    else
      throw "Could not find compute framework: no CUDA, ROCm, XPU version specified and Metal is not enabled";

  buildName =
    let
      inherit (import ./version-utils.nix { inherit lib; }) abiString flattenVersion;
      computeString =
        version:
        if isCuda version then
          "cu${flattenVersion (lib.versions.majorMinor version.cudaVersion)}"
        else if isRocm version then
          "rocm${flattenVersion (lib.versions.majorMinor version.rocmVersion)}"
        else if isMetal version then
          "metal"
        else if isXpu version then
          "xpu${flattenVersion (lib.versions.majorMinor version.xpuVersion)}"
        else
          throw "No compute framework set in Torch version";
    in
    version:
    if version.system == "aarch64-darwin" then
      "torch${flattenVersion version.torchVersion}-${computeString version}-${version.system}"
    else
      "torch${flattenVersion version.torchVersion}-${abiString version.cxx11Abi}-${computeString version}-${version.system}";

  # Build variants included in bundle builds.
  buildVariants =
    torchVersions:
    let
      bundleBuildVersions = lib.filter (version: version.bundleBuild or false);
    in
    lib.foldl' (
      acc: version:
      let
        path = [
          version.system
          (computeFramework version)
        ];
        pathVersions = lib.attrByPath path [ ] acc ++ [ (buildName version) ];
      in
      lib.recursiveUpdate acc (lib.setAttrByPath path pathVersions)
    ) { } (flattenSystems (bundleBuildVersions torchVersions));
}
