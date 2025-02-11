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
      torchVersions = [ "2.5" "2.6" ];
      buildConfigsWithoutCuda = lib.cartesianProduct {
        torchVersion = torchVersions;
        cxx11Abi = [
          true
          false
        ];
      };
    # Cartesian product of the build configurations and the CUDA versions
    # supported by the Torch in the build configuration. We can't use
    # `cartesianProduct` here because of this CUDA -> Torch dependency.
    cuda = lib.flatten (
      map (
        config:
        map (cudaVersion: config // { inherit cudaVersion; gpu = "cuda"; }) cudaVersionForTorch.${config.torchVersion}
      ) buildConfigsWithoutCuda
    );
    # ROCm always uses the C++11 ABI.
    rocm = map (torchVersion: { inherit torchVersion; gpu = "rocm"; cxx11Abi = true; }) torchVersions;
    in
    cuda ++ rocm;
}
