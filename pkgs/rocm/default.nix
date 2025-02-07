{
  lib,
  callPackage,
}:

let
  namesWithDeps = builtins.fromJSON (builtins.readFile ./deps.json);
  rocmPackages' = lib.mapAttrs (
    pname: metadata:
    callPackage ./generic.nix {
      inherit pname rocmPackages;
      inherit (metadata) deps bundleSrcs;
    }
  ) namesWithDeps;
  rocmPackages = callPackage ./overrides.nix { rocmPackages = rocmPackages'; };
in
rocmPackages // { clr = rocmPackages.hipcc; }
