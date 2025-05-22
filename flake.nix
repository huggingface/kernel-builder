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
        aarch64-linux
        x86_64-linux
      ];

      # Create an attrset { "<system>" = [ <buildset> ...]; ... }.
      buildSetPerSystem = builtins.listToAttrs (
        builtins.map (system: {
          name = system;
          value = import ./lib/buildsets.nix {
            inherit nixpkgs system;
            hf-nix = hf-nix.overlays.default;
          };
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
        allBuildVariantsJSON =
          let
            buildVariants = (import ./versions.nix { inherit (nixpkgs) lib; }).buildVariants;
          in
          builtins.toJSON (nixpkgs.lib.foldl' (acc: system: acc // buildVariants system) { } systems);
        genFlakeOutputs =
          { path, rev }:
          flake-utils.lib.eachSystem systems (
            system:
            let
              build = libPerSystem.${system};
              revUnderscored = builtins.replaceStrings [ "-" ] [ "_" ] rev;
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              devShells = rec {
                default = devShells."torch27-cxx11-cu126-${system}";
                test = testShells."torch27-cxx11-cu126-${system}";
                devShells = build.torchDevShells {
                  inherit path;
                  rev = revUnderscored;
                };
                testShells = build.torchExtensionShells {
                  inherit path;
                  rev = revUnderscored;
                };
              };
              packages = rec {
                default = bundle;
                bundle = build.buildTorchExtensionBundle {
                  inherit path;
                  rev = revUnderscored;
                };
                redistributable = build.buildDistTorchExtensions {
                  inherit path;
                  buildSets = buildSetPerSystem.${system};
                  rev = revUnderscored;
                };
                buildTree =
                  let
                    build2cmake = self.packages.${system}.build2cmake;
                    src = build.mkSourceSet path;
                  in
                  pkgs.runCommand "torch-extension-build-tree"
                    {
                      nativeBuildInputs = [ build2cmake ];
                      inherit src;
                      meta = {
                        description = "Build tree for torch extension with source files and CMake configuration";
                      };
                    }
                    ''
                      # Copy sources
                      install -dm755 $out/src
                      cp -r $src/. $out/src/

                      # Generate cmake files
                      build2cmake generate-torch --ops-id "${revUnderscored}" $src/build.toml $out --force
                    '';
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
        formatter = pkgs.nixfmt-tree;

        packages = rec {
          build2cmake = pkgs.callPackage ./pkgs/build2cmake { };

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
              filterDist = lib.filter (output: output != "dist");
              # Get all `torch` outputs except for `dist`. Not all outputs
              # are dependencies of `out`, but we'll need the `cxxdev` and
              # `dev` outputs for kernel builds.
              torchOutputs = builtins.listToAttrs (
                lib.flatten (
                  # Map over build sets.
                  map (
                    buildSet:
                    # Map over all outputs of `torch` in a buildset.
                    map (output: {
                      name = "${buildVersion buildSet}-${output}";
                      value = buildSet.torch.${output};
                    }) (filterDist buildSet.torch.outputs)
                  ) buildSets
                )
              );
              oldLinuxStdenvs = builtins.listToAttrs (
                map (buildSet: {
                  name = "stdenv-${buildVersion buildSet}";
                  value = buildSet.pkgs.stdenvGlibc_2_27;
                }) buildSets
              );
            in
            pkgs.linkFarm "packages-for-cache" (torchOutputs // oldLinuxStdenvs);
        };
      }
    )
    // {
      inherit lib;
    };
}
