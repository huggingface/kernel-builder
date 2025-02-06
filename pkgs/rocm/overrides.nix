{
  lib,
  callPackage,
  rocmPackages,
}:
let 
  applyOverrides = overrides:
    let
      rocmPackages' = lib.mapAttrs
        (name: value: rocmPackages.${name}.overrideAttrs (callPackage value {}))
        overrides;
    in
      rocmPackages // rocmPackages';
in
  applyOverrides {
    hipcc =
    { }:
    prevAttrs: {
      passthru = prevAttrs.passthru or {} // {
        gpuTargets = lib.forEach [
          "803"
          "900"
          "906"
          "908"
          "90a"
          "940"
          "941"
          "942"
          "1010"
          "1012"
          "1030"
          "1100"
          "1101"
          "1102"
        ] (target: "gfx${target}");
      };
    };
  }

