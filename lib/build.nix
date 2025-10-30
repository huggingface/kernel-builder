{
  lib,

# Every `buildSets` argument is a list of build sets. Each build set is
# a attrset of the form
#
#     { pkgs = <nixpkgs>, torch = <torch drv> }
#
# The Torch derivation is built as-is. So e.g. the ABI version should
# already be set.
}:

let
  abi = torch: if torch.passthru.cxx11Abi then "cxx11" else "cxx98";
  buildName = (import ./build-variants.nix { inherit lib; }).buildName;
  supportedCudaCapabilities = builtins.fromJSON (
    builtins.readFile ../build2cmake/src/cuda_supported_archs.json
  );
  inherit (import ./torch-version-utils.nix { inherit lib; })
    isCuda
    isMetal
    isRocm
    isXpu
    ;
  inherit (import ./build-variants.nix { inherit lib; }) computeFramework;
in
rec {
  resolveDeps = import ./deps.nix { inherit lib; };

  readToml = path: builtins.fromTOML (builtins.readFile path);

  validateBuildConfig =
    buildToml:
    let
      kernels = lib.attrValues (buildToml.kernel or { });
      hasOldUniversal = builtins.hasAttr "universal" (buildToml.torch or { });
      hasLanguage = lib.any (kernel: kernel ? language) kernels;

    in
    assert lib.assertMsg (!hasOldUniversal && !hasLanguage) ''
      build.toml seems to be of an older version, update it with:
            build2cmake update-build build.toml'';
    buildToml;

  backends =
    buildToml:
    let
      kernels = lib.attrValues (buildToml.kernel or { });
      kernelBackend = kernel: kernel.backend;
      init = {
        cuda = false;
        metal = false;
        rocm = false;
        xpu = false;
      };
    in
    lib.foldl (backends: kernel: backends // { ${kernelBackend kernel} = true; }) init kernels;

  readBuildConfig = path: validateBuildConfig (readToml (path + "/build.toml"));

  srcFilter =
    src: name: type:
    type == "directory" || lib.any (suffix: lib.hasSuffix suffix name) src;

  # Source set function to create a fileset for a path
  mkSourceSet = import ./source-set.nix { inherit lib; };

  # Filter buildsets that are applicable to a given kernel build config.
  filterApplicableBuildSets =
    buildToml: buildSets:
    let
      backends' = backends buildToml;
      minCuda = buildToml.general.cuda-minver or "11.8";
      maxCuda = buildToml.general.cuda-maxver or "99.9";
      versionBetween =
        minver: maxver: ver:
        builtins.compareVersions ver minver >= 0 && builtins.compareVersions ver maxver <= 0;
      supportedBuildSet =
        buildSet:
        let
          backendSupported =
            (isCuda buildSet.buildConfig && backends'.cuda)
            || (isRocm buildSet.buildConfig && backends'.rocm)
            || (isMetal buildSet.buildConfig && backends'.metal)
            || (isXpu buildSet.buildConfig && backends'.xpu)
            || (buildToml.general.universal or false);
          cudaVersionSupported =
            !(isCuda buildSet.buildConfig)
            || versionBetween minCuda maxCuda buildSet.pkgs.cudaPackages.cudaMajorMinorVersion;
        in
        backendSupported && cudaVersionSupported;
    in
    builtins.filter supportedBuildSet buildSets;

  applicableBuildSets =
    { path, buildSets }: filterApplicableBuildSets (readBuildConfig path) buildSets;

  # Build a single Torch extension.
  mkTorchExtension =
    {
      buildConfig,
      extension,
      pkgs,
      torch,
      bundleBuild,
    }:
    {
      path,
      rev,
      doGetKernelCheck,
      stripRPath ? false,
    }:
    let
      inherit (lib) fileset;
      buildToml = readBuildConfig path;
      kernels = lib.filterAttrs (_: kernel: computeFramework buildConfig == kernel.backend) (
        buildToml.kernel or { }
      );
      extraDeps = resolveDeps {
        inherit pkgs torch;
        deps = lib.unique (lib.flatten (lib.mapAttrsToList (_: kernel: kernel.depends) kernels));
      };

      # Use the mkSourceSet function to get the source
      src = mkSourceSet path;

      # Set number of threads to the largest number of capabilities.
      listMax = lib.foldl' lib.max 1;
      nvccThreads = listMax (
        lib.mapAttrsToList (
          _: kernel: builtins.length (kernel.cuda-capabilities or supportedCudaCapabilities)
        ) buildToml.kernel
      );
    in
    if buildToml.general.universal then
      # No torch extension sources? Treat it as a noarch package.

      extension.mkNoArchExtension {
        inherit
          src
          rev
          doGetKernelCheck
          ;
        extensionName = buildToml.general.name;
      }
    else
      extension.mkExtension {
        inherit
          doGetKernelCheck
          extraDeps
          nvccThreads
          src
          stripRPath
          rev
          ;

        extensionName = buildToml.general.name;
        doAbiCheck = true;
      };

  # Build multiple Torch extensions.
  mkDistTorchExtensions =
    {
      path,
      rev,
      doGetKernelCheck,
      bundleOnly,
      buildSets,
    }:
    let
      extensionForTorch =
        { path, rev }:
        buildSet: {
          name = buildName buildSet.buildConfig;
          value = mkTorchExtension buildSet {
            inherit path rev doGetKernelCheck;
            stripRPath = true;
          };
        };
      applicableBuildSets' =
        if bundleOnly then builtins.filter (buildSet: buildSet.bundleBuild) buildSets else buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch { inherit path rev; }) applicableBuildSets');

  mkTorchExtensionBundle =
    {
      path,
      rev,
      doGetKernelCheck,
      buildSets,
    }:
    let
      # We just need to get any nixpkgs for use by the path join.
      pkgs = (builtins.head buildSets).pkgs;
      extensions = mkDistTorchExtensions {
        inherit
          buildSets
          path
          rev
          doGetKernelCheck
          ;
        bundleOnly = true;
      };
      buildToml = readBuildConfig path;
      namePaths =
        if buildToml.general.universal then
          # Noarch, just get the first extension.
          { "torch-universal" = builtins.head (builtins.attrValues extensions); }
        else
          lib.mapAttrs (name: pkg: toString pkg) extensions;
    in
    import ./join-paths {
      inherit pkgs namePaths;
      name = "torch-ext-bundle";
    };

  # Get a development shell with the extension in PYTHONPATH. Handy
  # for running tests.
  torchExtensionShells =
    {
      path,
      rev,
      buildSets,
      doGetKernelCheck,
      pythonCheckInputs,
      pythonNativeCheckInputs,
    }:
    let
      shellForBuildSet =
        { path, rev }:
        buildSet:
        let
          pkgs = buildSet.pkgs;
          rocmSupport = pkgs.config.rocmSupport or false;
          mkShell = pkgs.mkShell.override { inherit (buildSet.extension) stdenv; };
        in
        {
          name = buildName buildSet.buildConfig;
          value = mkShell {
            nativeBuildInputs = with pkgs; pythonNativeCheckInputs python3.pkgs;

            buildInputs =
              with pkgs;
              [
                buildSet.torch
                python3.pkgs.pytest
              ]
              ++ (pythonCheckInputs python3.pkgs);
            shellHook = ''
              export PYTHONPATH=''${PYTHONPATH}:${
                mkTorchExtension buildSet { inherit path rev doGetKernelCheck; }
              }
            '';
          };
        };
    in
    builtins.listToAttrs (lib.map (shellForBuildSet { inherit path rev; }) buildSets);

  mkTorchDevShells =
    {
      path,
      rev,
      buildSets,
      doGetKernelCheck,
      pythonCheckInputs,
      pythonNativeCheckInputs,
    }:
    let
      shellForBuildSet =
        buildSet:
        let
          pkgs = buildSet.pkgs;
          rocmSupport = pkgs.config.rocmSupport or false;
          xpuSupport = pkgs.config.xpuSupport or false;
          mkShell = pkgs.mkShell.override { inherit (buildSet.extension) stdenv; };
        in
        {
          name = buildName buildSet.buildConfig;
          value = mkShell {
            nativeBuildInputs =
              with pkgs;
              [
                build2cmake
                kernel-abi-check
                python3.pkgs.venvShellHook
              ]
              ++ (pythonNativeCheckInputs python3.pkgs);
            buildInputs = with pkgs; [ python3.pkgs.pytest ] ++ (pythonCheckInputs python3.pkgs);
            inputsFrom = [ (mkTorchExtension buildSet { inherit path rev doGetKernelCheck; }) ];
            env = lib.optionalAttrs rocmSupport {
              PYTORCH_ROCM_ARCH = lib.concatStringsSep ";" buildSet.torch.rocmArchs;
              HIP_PATH = pkgs.rocmPackages.clr;
            };
            venvDir = "./.venv";
          };
        };
    in
    builtins.listToAttrs (lib.map shellForBuildSet buildSets);
}
