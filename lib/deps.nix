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
    "cutlass_3_8" = [
      pkgs.cutlass_3_8
    ];
    "cutlass_3_9" = [
      pkgs.cutlass_3_9
    ];
    "cutlass_sycl_3_9" = [
      pkgs.cutlass_sycl_3_9
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
