{ lib, torchVersions }:
let
  inherit (import ./torch-version-utils.nix { inherit lib; })
    flattenSystems
    isCuda
    isMetal
    isRocm
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
    else
      throw "Could not find compute framework: no CUDA or ROCm version specified and Metal is not enabled";

  # Build variants included in bundle builds.
  buildVariants =
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
        else
          throw "No compute framework set in Torch version";
      buildName =
        version:
        if version.system == "aarch64-darwin" then
          "torch${flattenVersion version.torchVersion}-${computeString version}-${version.system}"
        else
          "torch${flattenVersion version.torchVersion}-${abiString version.cxx11Abi}-${computeString version}-${version.system}";
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
