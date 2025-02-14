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
    "cutlass_2_10" = [
      pkgs.cutlass_2_10
    ];
    "cutlass_3_5" = [
      pkgs.cutlass_3_5
    ];
    "cutlass_3_6" = [
      pkgs.cutlass_3_6
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
