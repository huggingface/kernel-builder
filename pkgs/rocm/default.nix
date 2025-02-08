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
  composed = lib.composeManyExtensions [
    rocmPackages
    overrides
    (callPackage ./llvm.nix {})
    (callPackage ./clr.nix {})
  ];
in
lib.makeScope newScope (lib.extends composed (_: { }))
