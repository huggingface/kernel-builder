{
  nixpkgs,
  system,
}:

let
  inherit (nixpkgs) lib;

  overlay = import ../overlay.nix;

  # Get versions.
  inherit (import ../versions.nix { inherit lib; }) buildConfigs cudaVersions;

  buildVersion = import ./lib/build-version.nix;
  flattenVersion = version: lib.replaceStrings [ "." ] [ "_" ] (lib.versions.pad 2 version);

  # An overlay that overides CUDA to the given version.
  overlayForCudaVersion = cudaVersion: self: super: {
    cudaPackages = super."cudaPackages_${flattenVersion cudaVersion}";
  };

  # Construct the nixpkgs package set for the given versions.
  pkgsForVersions =
    pkgsByCudaVer:
    {
      cudaVersion,
      torchVersion,
      cxx11Abi,
    }:
    let
      pkgsForCudaVersion = pkgsByCudaVer.${cudaVersion};
      torch = pkgsForCudaVersion.python3.pkgs."torch_${flattenVersion torchVersion}".override {
        inherit cxx11Abi;
      };
    in
    {
      inherit torch;
      pkgs = pkgsForCudaVersion;
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
in
map (pkgsForVersions pkgsByCudaVer) buildConfigs
