{ lib }:
let
  inherit (import ./torch-version-utils.nix { inherit lib; })
    flattenSystems
    ;
in
rec {

  buildName =
    let
      inherit (import ./version-utils.nix { inherit lib; }) abiString flattenVersion;
      computeString =
        version:
        if version.backend == "cpu" then
          "cpu"
        else if version.backend == "cuda" then
          "cu${flattenVersion (lib.versions.majorMinor version.cudaVersion)}"
        else if version.backend == "rocm" then
          "rocm${flattenVersion (lib.versions.majorMinor version.rocmVersion)}"
        else if version.backend == "metal" then
          "metal"
        else if version.backend == "xpu" then
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
          version.backend
        ];
        pathVersions = lib.attrByPath path [ ] acc ++ [ (buildName version) ];
      in
      lib.recursiveUpdate acc (lib.setAttrByPath path pathVersions)
    ) { } (flattenSystems (bundleBuildVersions torchVersions));
}
