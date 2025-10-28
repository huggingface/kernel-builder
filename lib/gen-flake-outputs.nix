{
  lib,
  build,
  system,

  writeScriptBin,
  runCommand,

  path,
  buildSets,
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

  applicableBuildSets = build.applicableBuildSets { inherit path buildSets; };

  # For picking a default shell, etc. we want to use the following logic:
  #
  # - Prefer bundle builds over non-bundle builds.
  # - Prefer CUDA over other frameworks.
  # - Prefer newer Torch versions over older.
  # - Prefer older frameworks over newer (best compatibility).

  # Enrich the build configs with generic attributes for framework
  # order/version. Also make bundleBuild attr explicit.
  addSortOrder = map (
    set:
    let
      inherit (set) buildConfig;
    in
    set
    // {
      buildConfig =

        buildConfig // {
          bundleBuild = buildConfig.bundleBuild or false;
          framework =
            if buildConfig ? cudaVersion then
              "cuda"
            else if buildConfig ? rocmVersion then
              "rocm"
            else if buildConfig ? xpuVersion then
              "xpu"
            else if system == "aarch64-darwin" then
              "metal"
            else
              throw "Cannot determine framework for build set";
          frameworkOrder = if buildConfig ? cudaVersion then 0 else 1;
          frameworkVersion =
            buildConfig.cudaVersion or buildConfig.rocmVersion or buildConfig.xpuVersion or "0.0";
        };
    }
  );
  configCompare =
    setA: setB:
    let
      a = setA.buildConfig;
      b = setB.buildConfig;
    in
    if a.bundleBuild != b.bundleBuild then
      a.bundleBuild
    else if a.frameworkOrder != b.frameworkOrder then
      a.frameworkOrder < b.frameworkOrder
    else if a.torchVersion != b.torchVersion then
      builtins.compareVersions a.torchVersion b.torchVersion > 0
    else
      builtins.compareVersions a.frameworkVersion b.frameworkVersion < 0;
  buildSetsSorted = lib.sort configCompare (addSortOrder applicableBuildSets);
  bestBuildSet =
    if buildSetsSorted == [ ] then
      throw "No build variant is compatible with this system"
    else
      builtins.head buildSetsSorted;
  shellTorch = buildName bestBuildSet.buildConfig;
  headOrEmpty = l: if l == [ ] then [ ] else [ (builtins.head l) ];
in
{
  devShells = rec {
    default = devShells.${shellTorch};
    test = testShells.${shellTorch};
    devShells = build.mkTorchDevShells {
      inherit
        path
        doGetKernelCheck
        pythonCheckInputs
        pythonNativeCheckInputs
        ;
      buildSets = applicableBuildSets;
      rev = revUnderscored;
    };
    testShells = build.torchExtensionShells {
      inherit
        path
        doGetKernelCheck
        pythonCheckInputs
        pythonNativeCheckInputs
        ;
      buildSets = applicableBuildSets;
      rev = revUnderscored;
    };
  };
  packages =
    let
      bundle = build.mkTorchExtensionBundle {
        inherit path doGetKernelCheck;
        buildSets = applicableBuildSets;
        rev = revUnderscored;
      };
    in
    {
      inherit bundle;

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

      build-and-upload =
        let
          buildToml = build.readBuildConfig path;
          repo_id = lib.attrByPath [
            "general"
            "hub"
            "repo-id"
          ] "kernels-community/${buildToml.general.name}" buildToml;
          branch = lib.attrByPath [ "general" "hub" "branch" ] "main" buildToml;
        in
        writeScriptBin "build-and-upload" ''
          #!/usr/bin/env bash
          set -euo pipefail
          ${bestBuildSet.pkgs.python3.pkgs.kernels}/bin/kernels upload --repo-id ${repo_id} --branch ${branch} ${bundle}
        '';

      ci =
        let
          setsWithFramework =
            framework: builtins.filter (set: set.buildConfig.framework == framework) buildSetsSorted;
          # It is too costly to build all variants in CI, so we just build one per framework.
          onePerFramework =
            (headOrEmpty (setsWithFramework "cuda"))
            ++ (headOrEmpty (setsWithFramework "metal"))
            ++ (headOrEmpty (setsWithFramework "rocm"))
            ++ (headOrEmpty (setsWithFramework "xpu"));
        in
        build.mkTorchExtensionBundle {
          inherit path doGetKernelCheck;
          buildSets = onePerFramework;
          rev = revUnderscored;
        };

      kernels =
        bestBuildSet.pkgs.python3.withPackages (
          ps: with ps; [
            kernel-abi-check
            kernels
          ]
        )
        // {
          meta.mainProgram = "kernels";
        };

      redistributable = build.mkDistTorchExtensions {
        inherit path doGetKernelCheck;
        bundleOnly = false;
        rev = revUnderscored;
        buildSets = applicableBuildSets;
      };
    };
}
