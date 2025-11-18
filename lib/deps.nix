{
  lib,
  pkgs,
  torch,
}:

let
  cppDeps = {
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
    "cutlass_4_0" = [
      pkgs.cutlass_4_0
    ];
    "torch" = [
      torch
    ];
    "cutlass_sycl" = [ torch.xpuPackages.cutlass-sycl ];
    "metal-cpp" = [
      pkgs.metal-cpp.dev
    ];
  };
  pythonDeps = with pkgs.python3.pkgs; {
    "einops" = [ einops ];
    "nvidia-cutlass-dsl" = [ nvidia-cutlass-dsl ];
  };
  getCppDep = dep: cppDeps.${dep} or (throw "Unknown dependency: ${dep}");
  getPythonDep = dep: pythonDeps.${dep} or (throw "Unknown Python dependency: ${dep}");
in
{
  resolveCppDeps = deps: lib.flatten (map getCppDep deps);
  resolvePythonDeps = deps: lib.flatten (map getPythonDep deps);
}
