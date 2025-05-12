{ lib }:

rec {
  torchVersions = [
    {
      torchVersion = "2.6";
      cudaVersion = "11.8";
      cxx11Abi = false;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      cudaVersion = "11.8";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      cudaVersion = "12.4";
      cxx11Abi = false;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      cudaVersion = "12.4";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      cudaVersion = "12.6";
      cxx11Abi = false;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      cudaVersion = "12.6";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.6";
      rocmVersion = "6.2.4";
      cxx11Abi = true;
      upstreamVariant = true;
    }

    {
      torchVersion = "2.7";
      cudaVersion = "11.8";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.7";
      cudaVersion = "12.6";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.7";
      cudaVersion = "12.8";
      cxx11Abi = true;
      upstreamVariant = true;
    }
    {
      torchVersion = "2.7";
      rocmVersion = "6.3.4";
      cxx11Abi = true;
      upstreamVariant = true;
    }

    # Non-standard versions; not included in bundle builds.
    {
      torchVersion = "2.7";
      cudaVersion = "12.9";
      cxx11Abi = true;
    }
  ];

  cudaVersions =
    let
      withCuda = builtins.filter (torchVersion: torchVersion ? cudaVersion) torchVersions;
    in
    builtins.map (torchVersion: torchVersion.cudaVersion) withCuda;

  rocmVersions =
    let
      withRocm = builtins.filter (torchVersion: torchVersion ? rocmVersion) torchVersions;
    in
    builtins.map (torchVersion: torchVersion.rocmVersion) withRocm;

  # Upstream only builds aarch64 for CUDA >= 12.6.
  isCudaSupported =
    system: torchVersion:
    system == "x86_64-linux"
    || (
      system == "aarch64-linux" && lib.strings.versionAtLeast (torchVersion.cudaVersion or "0.0") "12.6"
    );

  # ROCm only builds on x86_64.
  isRocmSupported = system: torchVersion: system == "x86_64-linux" && torchVersion ? rocmVersion;

  isSupported =
    system: torchVersion:
    (isCudaSupported system torchVersion) || (isRocmSupported system torchVersion);

  computeFramework =
    buildConfig:
    if buildConfig ? cudaVersion then
      "cuda"
    else if buildConfig ? "rocmVersion" then
      "rocm"
    else
      throw "No CUDA or ROCm version specified";

  # All build configurations supported by Torch.
  buildConfigs =
    system:
    let
      supported = builtins.filter (isSupported system) torchVersions;
    in
    map (version: version // { gpu = computeFramework version; }) supported;

  # Upstream build variants.
  buildVariants =
    system:
    let
      inherit (import ./lib/version-utils.nix { inherit lib; }) abiString flattenVersion;
      computeString =
        buildConfig:
        if buildConfig.gpu == "cuda" then
          "cu${flattenVersion (lib.versions.majorMinor buildConfig.cudaVersion)}"
        else if buildConfig.gpu == "rocm" then
          "rocm${flattenVersion (lib.versions.majorMinor buildConfig.rocmVersion)}"
        else
          throw "Unknown compute framework: ${buildConfig.gpu}";
      buildName =
        buildConfig:
        "torch${flattenVersion buildConfig.torchVersion}-${abiString buildConfig.cxx11Abi}-${computeString buildConfig}-${system}";
      filterMap = f: xs: builtins.filter (x: x != null) (builtins.map f xs);
    in
    {
      ${system} = lib.zipAttrs (
        filterMap (
          buildConfig:
          if buildConfig.upstreamVariant or false then
            {
              ${buildConfig.gpu} = buildName buildConfig;
            }
          else
            null
        ) (buildConfigs system)
      );
    };
}
