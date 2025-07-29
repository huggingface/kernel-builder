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
            buildSets = buildSetPerSystem.${system};
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
                torchVersions = torchVersions';
              }).buildVariants;
          in
          builtins.toJSON buildVariants;
        genFlakeOutputs =
          {
            path,
            rev,

            # This option is not documented on purpose. You should not use it,
            # if a kernel cannot be imported, it is non-compliant. This is for
            # one exceptional case: packaging a third-party kernel (where you
            # want to stay close to upstream) where importing the kernel will
            # fail in a GPU-less sandbox. Even in that case, it's better to lazily
            # load the part with this functionality.
            doGetKernelCheck ? true,
            pythonCheckInputs ? pkgs: [ ],
            pythonNativeCheckInputs ? pkgs: [ ],
            torchVersions ? torchVersions',
          }:
          let
            buildSetPerSystem' = mkBuildSetsPerSystem torchVersions;
            buildPerSystem = mkBuildPerSystem buildSetPerSystem';
          in
          flake-utils.lib.eachSystem systems (
            system:
            let
              build = buildPerSystem.${system};
              revUnderscored = builtins.replaceStrings [ "-" ] [ "_" ] rev;
              pkgs = nixpkgs.legacyPackages.${system};
              shellTorch =
                if system == "aarch64-darwin" then "torch27-metal-${system}" else "torch27-cxx11-cu126-${system}";
            in
            {
              devShells = rec {
                default = devShells.${shellTorch};
                test = testShells.${shellTorch};
                devShells = build.torchDevShells {
                  inherit
                    path
                    doGetKernelCheck
                    pythonCheckInputs
                    pythonNativeCheckInputs
                    ;
                  rev = revUnderscored;
                };
                testShells = build.torchExtensionShells {
                  inherit
                    path
                    doGetKernelCheck
                    pythonCheckInputs
                    pythonNativeCheckInputs
                    ;
                  rev = revUnderscored;
                };
              };
              packages = rec {
                default = bundle;
                bundle = build.buildTorchExtensionBundle {
                  inherit path doGetKernelCheck;
                  rev = revUnderscored;
                };
                redistributable = build.buildDistTorchExtensions {
                  inherit path doGetKernelCheck;
                  buildSets = buildSetPerSystem'.${system};
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
      } // defaultBuildPerSystem;
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

        buildSets = defaultBuildSetsPerSystem.${system};

      in
      rec {
        formatter = pkgs.nixfmt-tree;

        packages = rec {
          build2cmake = pkgs.callPackage ./pkgs/build2cmake { };

          update-build = pkgs.writeShellScriptBin "update-build" ''
            ${build2cmake}/bin/build2cmake update-build ''${1:-build.toml}
          '';

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
            pkgs.linkFarm "packages-for-cache" (
              torchOutputs // lib.optionalAttrs nixpkgs.legacyPackages.${system}.stdenv.isLinux oldLinuxStdenvs
            );
        };
      }
    )
    // {
      inherit lib;
    };
}
