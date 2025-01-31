{ lib }:

rec {
  # Supported CUDA versions by Torch version.
  cudaVersionForTorch = {
    "2.5" = [ "11.8" "12.1" "12.4" ];
    "2.6" = [ "11.8" "12.4" "12.6" ];
  };

  cudaVersions = [ "11.8" "12.1" "12.4" "12.6" ];

  # All build configurations supported by Torch. We may want to split
  # this the CUDA versions by Torch version later, but the versions
  # are currently the same.
  buildConfigs =
    let
      buildConfigsWithoutCuda = lib.cartesianProduct {
        torchVersion = [
          "2.5"
          "2.6"
        ];
        cxx11Abi = [
          true
          false
        ];
      };
    in
    # Cartesian product of the build configurations and the CUDA versions
    # supported by the Torch in the build configuration. We can't use
    # `cartesianProduct` here because of this CUDA -> Torch dependency.
    lib.flatten (
      map (
        config:
        map (cudaVersion: config // { inherit cudaVersion; }) cudaVersionForTorch.${config.torchVersion}
      ) buildConfigsWithoutCuda
    );

}
