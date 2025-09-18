{
  build,
  buildSet,
  system,

  writeScriptBin,
  runCommand,

  path,
  rev ? null,
  self ? null,

  doGetKernelCheck,
  pythonCheckInputs,
  pythonNativeCheckInputs,
}:

let
  supportedFormat = ''
    kernel-builder.lib.genFlakeOutputs {
      inherit self;
      path = ./.;
    };
  '';
  flakeRev =
    if self != null then
      self.shortRev or self.dirtyShortRev or (builtins.warn ''
        Kernel is not in a git repository, this will create a non-reproducible build.
        This will not be supported in the future.
      '' self.lastModifiedDate)
    else if rev != null then
      builtins.warn "`rev` argument of `genFlakeOutputs` is deprecated, pass `self` as follows:\n\n${supportedFormat}" rev
    else
      throw "Flake's `self` must be passed to `genFlakeOutputs` as follows:\n\n${supportedFormat}";

  revUnderscored = builtins.replaceStrings [ "-" ] [ "_" ] flakeRev;
  shellTorch =
    if system == "aarch64-darwin" then "torch28-metal-${system}" else "torch28-cxx11-cu126-${system}";
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

    build-and-copy = writeScriptBin "build-and-copy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ ! -d build ]; then
        mkdir build
      fi

      for build_variant in ${bundle}/*; do
        build_variant=$(basename $build_variant)
        if [ -e build/$build_variant ]; then
          rm -rf build/$build_variant
        fi

        cp -r ${bundle}/$build_variant build/
      done

      chmod -R +w build
    '';

    bundle = build.buildTorchExtensionBundle {
      inherit path doGetKernelCheck;
      rev = revUnderscored;
    };
    redistributable = build.buildDistTorchExtensions {
      inherit path doGetKernelCheck;
      buildSets = buildSet;
      rev = revUnderscored;
    };
    buildTree =
      let
        src = build.mkSourceSet path;
      in
      runCommand "torch-extension-build-tree"
        {
          nativeBuildInputs = [ buildSet.pkgs.build2cmake ];
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
