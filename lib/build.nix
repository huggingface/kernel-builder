{
  lib,

  # List of build sets. Each build set is a attrset of the form
  #
  #     { pkgs = <nixpkgs>, torch = <torch drv> }
  #
  # The Torch derivation is built as-is. So e.g. the ABI version should
  # already be set.
  buildSets,
}:

let
  abi = torch: if torch.passthru.cxx11Abi then "cxx11" else "cxx98";
  torchBuildVersion = import ./build-version.nix;
  supportedCudaCapabilities = builtins.fromJSON (
    builtins.readFile ../build2cmake/src/cuda_supported_archs.json
  );
  inherit (import ./torch-version-utils.nix { inherit lib; })
    isCuda
    isMetal
    isRocm
    isXpu
    ;
  mkStdenv =
    buildSet: oldLinuxCompat:
    let
      inherit (buildSet) pkgs torch;
    in
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.stdenv
    else if oldLinuxCompat then
      # Uses CUDA stdenv when we are building for CUDA.
      pkgs.stdenvGlibc_2_27
    else if torch.cudaSupport then
      torch.cudaPackages.backendStdenv
    else
      pkgs.stdenv;

in
rec {
  resolveDeps = import ./deps.nix { inherit lib; };

  readToml = path: builtins.fromTOML (builtins.readFile path);

  validateBuildConfig =
    buildConfig:
    let
      kernels = lib.attrValues (buildConfig.kernel or { });
      hasOldUniversal = builtins.hasAttr "universal" (buildConfig.torch or { });
      hasLanguage = lib.any (kernel: kernel ? language) kernels;

    in
    assert lib.assertMsg (!hasOldUniversal && !hasLanguage) ''
      build.toml seems to be of an older version, update it with:
            build2cmake update-build build.toml'';
    buildConfig;

  backends =
    buildConfig:
    let
      kernels = lib.attrValues (buildConfig.kernel or { });
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
  tracedReadBuildConfig = path: readBuildConfig path;

  srcFilter =
    src: name: type:
    type == "directory" || lib.any (suffix: lib.hasSuffix suffix name) src;

  # Source set function to create a fileset for a path
  mkSourceSet = import ./source-set.nix { inherit lib; };

  # Filter buildsets that are applicable to a given kernel build config.
  applicableBuildSets =
    buildConfig: buildSets:
    let
      backends' = backends buildConfig;
      minCuda = buildConfig.general.cuda-minver or "11.8";
      maxCuda = buildConfig.general.cuda-maxver or "99.9";
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
            || (buildConfig.general.universal or false);
          cudaVersionSupported =
            !(isCuda buildSet.buildConfig)
            || versionBetween minCuda maxCuda buildSet.pkgs.cudaPackages.cudaMajorMinorVersion;
        in
        backendSupported && cudaVersionSupported;
    in
    builtins.filter supportedBuildSet buildSets;

  # Build a single Torch extension.
  buildTorchExtension =
    {
      buildConfig,
      pkgs,
      torch,
      bundleBuild,
    }:
    {
      path,
      rev,
      doGetKernelCheck,
      stripRPath ? false,
      oldLinuxCompat ? false,
    }:
    let
      inherit (lib) fileset;
      buildConfig = readBuildConfig path;
      kernels = buildConfig.kernel or { };
      extraDeps = resolveDeps {
        inherit pkgs torch;
        deps = lib.unique (lib.flatten (lib.mapAttrsToList (_: buildConfig: buildConfig.depends) kernels));
      };

      # Use the mkSourceSet function to get the source
      src = mkSourceSet path;

      # Set number of threads to the largest number of capabilities.
      listMax = lib.foldl' lib.max 1;
      nvccThreads = listMax (
        lib.mapAttrsToList (
          _: buildConfig: builtins.length (buildConfig.cuda-capabilities or supportedCudaCapabilities)
        ) buildConfig.kernel
      );
      stdenv = mkStdenv { inherit pkgs torch; } oldLinuxCompat;
    in
    if buildConfig.general.universal then
      # No torch extension sources? Treat it as a noarch package.
      pkgs.callPackage ./torch-extension-noarch ({
        inherit
          src
          rev
          torch
          doGetKernelCheck
          ;
        extensionName = buildConfig.general.name;
      })
    else
      pkgs.callPackage ./torch-extension ({
        inherit
          doGetKernelCheck
          extraDeps
          nvccThreads
          src
          stdenv
          stripRPath
          torch
          rev
          ;
        extensionName = buildConfig.general.name;
        doAbiCheck = oldLinuxCompat;
      });

  # Build multiple Torch extensions.
  buildNixTorchExtensions =
    { path, rev }:
    let
      extensionForTorch =
        { path, rev }:
        buildSet: {
          name = torchBuildVersion buildSet;
          value = buildTorchExtension buildSet { inherit path rev; };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch { inherit path rev; }) filteredBuildSets);

  # Build multiple Torch extensions.
  buildDistTorchExtensions =
    {
      buildSets,
      path,
      rev,
      doGetKernelCheck,
    }:
    let
      extensionForTorch =
        { path, rev }:
        buildSet: {
          name = torchBuildVersion buildSet;
          value = buildTorchExtension buildSet {
            inherit path rev doGetKernelCheck;
            stripRPath = true;
            oldLinuxCompat = true;
          };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch { inherit path rev; }) filteredBuildSets);

  buildTorchExtensionBundle =
    {
      path,
      rev,
      doGetKernelCheck,
    }:
    let
      # We just need to get any nixpkgs for use by the path join.
      pkgs = (builtins.head buildSets).pkgs;
      bundleBuildSets = builtins.filter (buildSet: buildSet.bundleBuild) buildSets;
      extensions = buildDistTorchExtensions {
        inherit path rev doGetKernelCheck;
        buildSets = bundleBuildSets;
      };
      buildConfig = readBuildConfig path;
      namePaths =
        if buildConfig.general.universal then
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
          stdenv = mkStdenv buildSet false;
          mkShell = pkgs.mkShell.override { inherit stdenv; };
        in
        {
          name = torchBuildVersion buildSet;
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
                buildTorchExtension buildSet { inherit path rev doGetKernelCheck; }
              }
            '';
          };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (shellForBuildSet { inherit path rev; }) filteredBuildSets);

  torchDevShells =
    {
      path,
      rev,
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
          stdenv = mkStdenv buildSet false;
          mkShell = pkgs.mkShell.override { inherit stdenv; };
        in
        {
          name = torchBuildVersion buildSet;
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
            inputsFrom = [ (buildTorchExtension buildSet { inherit path rev doGetKernelCheck; }) ];
            env = lib.optionalAttrs rocmSupport {
              PYTORCH_ROCM_ARCH = lib.concatStringsSep ";" buildSet.torch.rocmArchs;
              HIP_PATH = pkgs.rocmPackages.clr;
            };
            venvDir = "./.venv";
          };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map shellForBuildSet filteredBuildSets);
}
