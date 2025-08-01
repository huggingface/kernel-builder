{
  nixpkgs,
  system,
  hf-nix,
  torchVersions,
}:

let
  inherit (nixpkgs) lib;

  overlay = import ../overlay.nix;

  inherit (import ./torch-version-utils.nix { inherit lib; })
    flattenSystems
    isCuda
    isMetal
    isRocm
    ;

  # All build configurations supported by Torch.
  buildConfigs =
    system:
    let
      filterMap = f: xs: builtins.filter (x: x != null) (builtins.map f xs);
    in
    filterMap (version: if version.system == system then version else null) (
      flattenSystems torchVersions
    );

  cudaVersions =
    let
      withCuda = builtins.filter (torchVersion: torchVersion ? cudaVersion) torchVersions;
    in
    lib.unique (builtins.map (torchVersion: torchVersion.cudaVersion) withCuda);

  rocmVersions =
    let
      withRocm = builtins.filter (torchVersion: torchVersion ? rocmVersion) torchVersions;
    in
    lib.unique (builtins.map (torchVersion: torchVersion.rocmVersion) withRocm);

  flattenVersion = version: lib.replaceStrings [ "." ] [ "_" ] (lib.versions.pad 2 version);

  # An overlay that overides CUDA to the given version.
  overlayForCudaVersion = cudaVersion: self: super: {
    cudaPackages = super."cudaPackages_${flattenVersion cudaVersion}";
  };

  overlayForRocmVersion = rocmVersion: self: super: {
    rocmPackages = super."rocmPackages_${flattenVersion rocmVersion}";
  };

  # Construct the nixpkgs package set for the given versions.
  pkgsForVersions =
    buildConfig@{
      cudaVersion ? null,
      metal ? false,
      rocmVersion ? null,
      torchVersion,
      cxx11Abi,
      system,
      bundleBuild ? false,
    }:
    let
      pkgs =
        if isCuda buildConfig then
          pkgsByCudaVer.${cudaVersion}
        else if isRocm buildConfig then
          pkgsByRocmVer.${rocmVersion}
        else if isMetal buildConfig then
          pkgsForMetal
        else
          throw "No compute framework set in Torch version";
      torch = pkgs.python3.pkgs."torch_${flattenVersion torchVersion}".override {
        inherit cxx11Abi;
      };
    in
    {
      inherit
        buildConfig
        pkgs
        torch
        bundleBuild
        ;
    };

  pkgsForMetal = import nixpkgs {
    inherit system;
    overlays = [
      hf-nix
      overlay
    ];
  };

  # Instantiate nixpkgs for the given CUDA versions. Returns
  # an attribute set like `{ "12.4" = <nixpkgs with 12.4>; ... }`.
  pkgsForCudaVersions =
    cudaVersions:
    builtins.listToAttrs (
      map (cudaVersion: {
        name = cudaVersion;
        value = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
          overlays = [
            hf-nix
            overlay
            (overlayForCudaVersion cudaVersion)
          ];
        };
      }) cudaVersions
    );

  pkgsByCudaVer = pkgsForCudaVersions cudaVersions;

  pkgsForRocmVersions =
    rocmVersions:
    builtins.listToAttrs (
      map (rocmVersion: {
        name = rocmVersion;
        value = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            rocmSupport = true;
          };
          overlays = [
            hf-nix
            overlay
            (overlayForRocmVersion rocmVersion)
          ];
        };
      }) rocmVersions
    );

  pkgsByRocmVer = pkgsForRocmVersions rocmVersions;

in
map pkgsForVersions (buildConfigs system)
