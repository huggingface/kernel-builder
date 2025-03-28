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
in
rec {
  resolveDeps = import ./deps.nix { inherit lib; };

  readToml = path: builtins.fromTOML (builtins.readFile path);

  readBuildConfig = path: readToml (path + "/build.toml");

  srcFilter =
    src: name: type:
    type == "directory" || lib.any (suffix: lib.hasSuffix suffix name) src;

  # Source set function to create a fileset for a path
  mkSourceSet = import ./source-set.nix { inherit lib; };

  languages =
    buildConfig:
    let
      kernels = lib.attrValues (buildConfig.kernel or { });
      kernelLang = kernel: kernel.language or "cuda";
      init = {
        cuda = false;
        cuda-hipify = false;
      };
    in
    lib.foldl (langs: kernel: langs // { ${kernelLang kernel} = true; }) init kernels;

  applicableBuildSets =
    buildConfig: buildSets:
    let
      languages' = languages buildConfig;
      supportedBuildSet =
        buildSet:
        (buildSet.gpu == "cuda" && (languages'.cuda || languages'.cuda-hipify))
        || (buildSet.gpu == "rocm" && languages'.cuda-hipify)
        || (buildConfig.torch.universal or false);
    in
    builtins.filter supportedBuildSet buildSets;

  # Build a single Torch extension.
  buildTorchExtension =
    {
      gpu,
      pkgs,
      torch,
    }:
    {
      path,
      rev,
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
          _: buildConfig: builtins.length buildConfig.cuda-capabilities
        ) buildConfig.kernel
      );
      stdenv = if oldLinuxCompat then pkgs.stdenvGlibc_2_27 else pkgs.cudaPackages.backendStdenv;
    in
    if buildConfig.torch.universal or false then
      # No torch extension sources? Treat it as a noarch package.
      pkgs.callPackage ./torch-extension-noarch ({
        inherit src;
        extensionName = buildConfig.general.name;
      })
    else
      pkgs.callPackage ./torch-extension ({
        inherit
          extraDeps
          nvccThreads
          src
          stdenv
          stripRPath
          torch
          rev
          ;
        extensionName = buildConfig.general.name;
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
    { path, rev }:
    let
      extensionForTorch =
        { path, rev }:
        buildSet: {
          name = torchBuildVersion buildSet;
          value = buildTorchExtension buildSet {
            inherit path rev;
            stripRPath = true;
            oldLinuxCompat = true;
          };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch { inherit path rev; }) filteredBuildSets);

  buildTorchExtensionBundle =
    { path, rev }:
    let
      # We just need to get any nixpkgs for use by the path join.
      pkgs = (builtins.head buildSets).pkgs;
      extensions = buildDistTorchExtensions { inherit path rev; };
      buildConfig = readBuildConfig path;
      namePaths =
        if buildConfig.torch.universal or false then
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
    { path, rev }:
    let
      shellForBuildSet =
        { path, rev }:
        buildSet: {
          name = torchBuildVersion buildSet;
          value =
            with buildSet.pkgs;
            mkShell {
              buildInputs = [
                (python3.withPackages (
                  ps: with ps; [
                    buildSet.torch
                    pytest
                  ]
                ))
              ];
              shellHook = ''
                export PYTHONPATH=${buildTorchExtension buildSet { inherit path rev; }}
              '';
            };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (shellForBuildSet { inherit path rev; }) filteredBuildSets);
}
