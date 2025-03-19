{ lib }:

rec {
  torchCudaVersions = {
    "2.5" = {
      cudaVersions = [
        "11.8"
        "12.1"
        "12.4"
      ];
      cxx11Abi = [
        true
        false
      ];
    };
    "2.6" = {
      cudaVersions = [
        "11.8"
        "12.4"
        "12.6"
      ];
      cxx11Abi = [
        true
        false
      ];
    };
  };

  cudaVersions = lib.flatten (
    builtins.map (versionInfo: versionInfo.cudaVersions) (builtins.attrValues torchCudaVersions)
  );

  # All build configurations supported by Torch.
  buildConfigs =
    let
      cuda = lib.flatten (
        lib.mapAttrsToList (
          torchVersion: versionInfo:
          lib.cartesianProduct {
            cudaVersion = versionInfo.cudaVersions;
            cxx11Abi = versionInfo.cxx11Abi;
            gpu = [ "cuda" ];
            torchVersion = [ torchVersion ];
          }
        ) torchCudaVersions
      );
      # ROCm always uses the C++11 ABI.
      rocm =
        map
          (torchVersion: {
            inherit torchVersion;
            gpu = "rocm";
            cxx11Abi = true;
          })
          [
            "2.5"
            "2.6"
          ];
    in
    cuda ++ rocm;
}
