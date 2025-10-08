{
  lib,
  build,
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
  inherit (import ./build-variants.nix { inherit lib; }) buildName;

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

  # For picking a default shell, etc. we want to use the following logic:
  #
  # - Prefer bundle builds over non-bundle builds.
  # - Prefer CUDA over other frameworks.
  # - Prefer newer Torch versions over older.
  # - Prefer older frameworks over newer (best compatibility).

  # Enrich the build configs with generic attributes for framework
  # order/version. Also make bundleBuild attr explicit.
  buildConfigs = map (
    set:
    let
      inherit (set) buildConfig;
    in
    buildConfig
    // {
      bundleBuild = buildConfig.bundleBuild or false;
      frameworkOrder = if buildConfig ? cudaVersion then 0 else 1;
      frameworkVersion =
        buildConfig.cudaVersion or buildConfig.rocmVersion or buildConfig.xpuVersion or "0.0";
    }
  ) (build.applicableBuildSets path);
  configCompare =
    a: b:
    if a.bundleBuild != b.bundleBuild then
      a.bundleBuild
    else if a.frameworkOrder != b.frameworkOrder then
      a.frameworkOrder < b.frameworkOrder
    else if a.torchVersion != b.torchVersion then
      builtins.compareVersions a.torchVersion b.torchVersion > 0
    else
      builtins.compareVersions a.frameworkVersion b.frameworkVersion < 0;
  buildConfigsSorted = lib.sort configCompare buildConfigs;
  shellTorch =
    if buildConfigsSorted == [ ] then
      throw "No build variant is compatible with this system"
    else
      buildName (builtins.head buildConfigsSorted);
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
      bundleOnly = false;
      rev = revUnderscored;
    };
  };
}
