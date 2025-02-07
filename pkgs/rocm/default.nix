{
  lib,
  callPackage,
  newScope,
}:

let
  namesWithDeps = builtins.fromJSON (builtins.readFile ./deps.json);
  # Package set without overrides.
  rocmPackages =
    final: prev:
    lib.mapAttrs (
      pname: metadata:
      callPackage ./generic.nix {
        inherit pname;
        inherit (metadata) deps bundleSrcs;
        rocmPackages = final;
      }
    ) namesWithDeps;
  overrides = callPackage ./overrides.nix { };
  aliases = final: prev: { clr = final.hipcc; };
  composed = lib.composeManyExtensions [
    rocmPackages
    overrides
    (callPackage ./llvm.nix {})
    aliases
  ];
in
lib.makeScope newScope (lib.extends composed (_: { }))
