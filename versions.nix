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

  torchRocmVersions = {
    "2.6" = {
      rocmVersions = [
        "6.2.4"
      ];
      cxx11Abi = [
        true
      ];
    };
  };

  # Upstream only builds aarch64 for CUDA >= 12.6.
  cudaSupported =
    system: cudaVersion:
    system == "x86_64-linux"
    || (system == "aarch64-linux" && lib.strings.versionAtLeast cudaVersion "12.6");

  cudaVersions = lib.flatten (
    builtins.map (versionInfo: versionInfo.cudaVersions) (builtins.attrValues torchCudaVersions)
  );

  rocmVersions = lib.flatten (
    builtins.map (versionInfo: versionInfo.rocmVersions) (builtins.attrValues torchRocmVersions)
  );

  # All build configurations supported by Torch.
  buildConfigs =
    system:
    let
      cuda = lib.flatten (
        lib.mapAttrsToList (
          torchVersion: versionInfo:
          lib.cartesianProduct {
            cudaVersion = builtins.filter (cudaSupported system) versionInfo.cudaVersions;
            cxx11Abi = versionInfo.cxx11Abi;
            gpu = [ "cuda" ];
            torchVersion = [ torchVersion ];
          }
        ) torchCudaVersions
      );
      rocm = lib.flatten (
        lib.mapAttrsToList (
          torchVersion: versionInfo:
          lib.cartesianProduct {
            rocmVersion = versionInfo.rocmVersions;
            cxx11Abi = versionInfo.cxx11Abi;
            gpu = [ "rocm" ];
            torchVersion = [ torchVersion ];
          }
        ) torchRocmVersions
      );
    in
    cuda ++ (lib.optionals (system == "x86_64-linux") rocm);
}
