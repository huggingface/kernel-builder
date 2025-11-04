{
  description = "Kernel builder";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.follows = "hf-nix/nixpkgs";
    flake-compat.url = "github:edolstra/flake-compat";
    hf-nix.url = "github:huggingface/hf-nix";
  };

  outputs =
    {
      self,
      flake-compat,
      flake-utils,
      hf-nix,
      nixpkgs,
    }:
    let
      systems = with flake-utils.lib.system; [
        aarch64-darwin
        aarch64-linux
        x86_64-linux
      ];

      torchVersions' = import ./versions.nix;

      # Create an attrset { "<system>" = [ <buildset> ...]; ... }.
      mkBuildSetsPerSystem =
        torchVersions:
        builtins.listToAttrs (
          builtins.map (system: {
            name = system;
            value = import ./lib/build-sets.nix {
              inherit nixpkgs system torchVersions;
              hf-nix = hf-nix.overlays.default;
            };
          }) systems
        );

      defaultBuildSetsPerSystem = mkBuildSetsPerSystem torchVersions';

      mkBuildPerSystem =
        buildSetPerSystem:
        builtins.mapAttrs (
          system: buildSet:
          import lib/build.nix {
            inherit (nixpkgs) lib;
          }
        ) buildSetPerSystem;

      defaultBuildPerSystem = mkBuildPerSystem defaultBuildSetsPerSystem;

      # The lib output consists of two parts:
      #
      # - Per-system build functions.
      # - `genFlakeOutputs`, which can be used by downstream flakes to make
      #   standardized outputs (for all supported systems).
      lib = {
        allBuildVariantsJSON =
          let
            buildVariants =
              (import ./lib/build-variants.nix {
                inherit (nixpkgs) lib;
              }).buildVariants
                torchVersions';
          in
          builtins.toJSON buildVariants;
        genFlakeOutputs =
          {
            path,
            rev ? null,
            self ? null,

            # This option is not documented on purpose. You should not use it,
            # if a kernel cannot be imported, it is non-compliant. This is for
            # one exceptional case: packaging a third-party kernel (where you
            # want to stay close to upstream) where importing the kernel will
            # fail in a GPU-less sandbox. Even in that case, it's better to lazily
            # load the part with this functionality.
            doGetKernelCheck ? true,
            pythonCheckInputs ? pkgs: [ ],
            pythonNativeCheckInputs ? pkgs: [ ],
            torchVersions ? _: torchVersions',
          }:
          assert
            (builtins.isFunction torchVersions)
            || abort "`torchVersions` must be a function taking one argument (the default version set)";
          let
            buildSetPerSystem = mkBuildSetsPerSystem (torchVersions torchVersions');
            buildPerSystem = mkBuildPerSystem buildSetPerSystem;
          in
          flake-utils.lib.eachSystem systems (
            system:
            nixpkgs.legacyPackages.${system}.callPackage ./lib/gen-flake-outputs.nix {
              inherit
                system
                path
                rev
                self
                doGetKernelCheck
                pythonCheckInputs
                pythonNativeCheckInputs
                ;
              build = buildPerSystem.${system};
              buildSets = buildSetPerSystem.${system};
            }
          );
      }
      // defaultBuildPerSystem;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        # Plain nixkpgs that we use to access utility funtions.
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (nixpkgs) lib;

        buildName = (import ./lib/build-variants.nix { inherit lib; }).buildName;

        buildSets = defaultBuildSetsPerSystem.${system};

      in
      rec {
        formatter = pkgs.nixfmt-tree;

        packages =
          let
            # Dependencies that should be cached, the structure of the output
            # path is: <build variant>/<dependency>-<output>
            mkForCache =
              buildSets:
              let
                filterDist = lib.filter (output: output != "dist");
                # Get all outputs except for `dist` (which is the built wheel for Torch).
                allOutputs =
                  drv:
                  map (output: {
                    name = "${drv.pname or drv.name}-${output}";
                    path = drv.${output};
                  }) (filterDist drv.outputs or [ "out" ]);
                buildSetOutputs =
                  buildSet:
                  with buildSet.pkgs;
                  (
                    allOutputs buildSet.torch
                    ++ lib.concatMap allOutputs buildSet.extension.extraBuildDeps
                    ++ allOutputs build2cmake
                    ++ allOutputs kernel-abi-check
                    ++ allOutputs python3Packages.kernels
                    ++ lib.optionals stdenv.hostPlatform.isLinux (allOutputs stdenvGlibc_2_27)
                  );
                buildSetLinkFarm =
                  buildSet: pkgs.linkFarm (buildName buildSet.buildConfig) (buildSetOutputs buildSet);
              in
              pkgs.linkFarm "packages-for-cache" (
                map (buildSet: {
                  name = buildName (buildSet.buildConfig);
                  path = buildSetLinkFarm buildSet;
                }) buildSets
              );

          in
          rec {
            build2cmake = pkgs.callPackage ./pkgs/build2cmake { };

            kernel-abi-check = pkgs.callPackage ./pkgs/kernel-abi-check { };

            update-build = pkgs.writeShellScriptBin "update-build" ''
              ${build2cmake}/bin/build2cmake update-build ''${1:-build.toml}
            '';

            forCache = mkForCache (
              builtins.filter (buildSet: buildSet.buildConfig.bundleBuild or false) buildSets
            );

            forCacheNonBundle = mkForCache (
              builtins.filter (buildSet: !(buildSet.buildConfig.bundleBuild or false)) buildSets
            );

            # This package set is exposed so that we can prebuild the Torch versions.
            torch = builtins.listToAttrs (
              map (buildSet: {
                name = buildName (buildSet.buildConfig);
                value = buildSet.torch;
              }) buildSets
            );

          };
      }
    )
    // {
      inherit lib;
    };
}
