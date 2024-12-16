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
    let
      systems = [ flake-utils.lib.system.x86_64-linux ];

      # Create an attrset { "<system>" = [ <buildset> ...]; ... }.
      buildSetPerSystem = builtins.listToAttrs (
        builtins.map (system: {
          name = system;
          value = import ./lib/buildsets.nix { inherit nixpkgs system; };
        }) systems
      );

      libPerSystem = builtins.mapAttrs (
        system: buildSet:
        import lib/build.nix {
          inherit (nixpkgs) lib;
          buildSets = buildSetPerSystem.${system};
        }
      ) buildSetPerSystem;

      # The lib output consists of two parts:
      #
      # - Per-system build functions.
      # - `genFlakeOutputs`, which can be used by downstream flakes to make
      #   standardized outputs (for all supported systems).
      lib = {
        genFlakeOutputs =
          path:
          flake-utils.lib.eachSystem systems (
            system:
            let
              build = libPerSystem.${system};
            in
            {
              devShells = rec {
                default = shells.torch24-cxx98-cu124-x86_64-linux;
                shells = build.torchExtensionShells path;
              };
              packages = {
                bundle = build.buildTorchExtensionBundle path;
                redistributable = build.buildDistTorchExtensions path;
              };
            }
          );
      } // libPerSystem;

    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        # Plain nixkpgs that we use to access utility funtions.
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (nixpkgs) lib;

        buildVersion = import ./lib/build-version.nix;

        buildSets = buildSetPerSystem.${system};

      in
      rec {
        formatter = pkgs.nixfmt-rfc-style;

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
    )
    // {
      inherit lib;
    };
}
