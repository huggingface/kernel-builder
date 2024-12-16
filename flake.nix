{
  description = "Kernel builder";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    {
      self,
      flake-compat,
      flake-utils,
      nixpkgs,
    }:
    flake-utils.lib.eachSystem [ flake-utils.lib.system.x86_64-linux ] (
      system:
      let
        # Plain nixkpgs that we use to access utility funtions.
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib;

        buildVersion = import ./lib/build-version.nix;

        buildSets = import ./lib/buildsets.nix { inherit nixpkgs pkgs; };

      in
      rec {
        formatter = pkgs.nixfmt-rfc-style;
        lib = import lib/build.nix {
          inherit (pkgs) lib;
          inherit buildSets;
        };
        packages = rec {
          # This package set is exposed so that we can prebuild the Torch versions.
          torch = builtins.listToAttrs (
            map (buildSet: {
              name = buildVersion buildSet;
              value = buildSet.torch;
            }) buildSets
          );

          # Dependencies that should be cached.
          forCache =
            let
              oldLinuxStdenvs = builtins.listToAttrs (
                map (buildSet: {
                  name = "stdenv-${buildVersion buildSet}";
                  value = buildSet.pkgs.stdenvGlibc_2_27;
                }) buildSets
              );
            in
            pkgs.linkFarm "packages-for-cache" (torch // oldLinuxStdenvs);
        };
      }
    );
}
