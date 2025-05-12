{
  nixpkgs,
  system,
  rocm,
}:

let
  inherit (nixpkgs) lib;

  overlay = import ../overlay.nix;

  # Get versions.
  inherit (import ../versions.nix { inherit lib; }) buildConfigs cudaVersions rocmVersions;

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
    pkgsByCudaVer:
    {
      gpu,
      cudaVersion ? "",
      rocmVersion ? "",
      torchVersion,
      cxx11Abi,
      upstreamVariant ? false,
    }:
    let
      pkgs = if gpu == "cuda" then pkgsByCudaVer.${cudaVersion} else pkgsByRocmVer.${rocmVersion};
      torch = pkgs.python3.pkgs."torch_${flattenVersion torchVersion}".override {
        inherit cxx11Abi;
      };
    in
    {
      inherit
        gpu
        pkgs
        torch
        upstreamVariant
        ;
    };

  pkgsForRocm = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      rocmSupport = true;
    };
    overlays = [
      overlay
      rocm
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
            overlay
            rocm
            (overlayForRocmVersion rocmVersion)
          ];
        };
      }) rocmVersions
    );

  pkgsByRocmVer = pkgsForRocmVersions rocmVersions;

in
map (pkgsForVersions pkgsByCudaVer) (buildConfigs system)
