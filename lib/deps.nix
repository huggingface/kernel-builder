{
  lib,
}:

{
  pkgs,
  torch,
  deps,
}:

let
  knownDeps = with pkgs.cudaPackages; {
    "cutlass" = [
      pkgs.cutlass
    ];
    "torch" = [
      torch
      torch.cxxdev
    ];
  };

in
let
  depToPkg =
    dep:
    assert lib.assertMsg (builtins.hasAttr dep knownDeps) "Unknown dependency: ${dep}";
    knownDeps.${dep};
in
lib.flatten (map depToPkg deps)
