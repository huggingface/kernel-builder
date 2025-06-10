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
  applicableBuildSets =
    buildConfig: buildSets:
    let
      backends' = backends buildConfig;
      supportedBuildSet =
        buildSet:
        (buildSet.gpu == "cuda" && backends'.cuda)
        || (buildSet.gpu == "rocm" && backends'.rocm)
        || (buildSet.gpu == "metal" && backends'.metal)
        || (buildConfig.general.universal or false);
    in
    builtins.filter supportedBuildSet buildSets;

  # Build a single Torch extension.
  buildTorchExtension =
    {
      gpu,
      pkgs,
      torch,
      upstreamVariant,
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
          _: buildConfig: builtins.length (buildConfig.cuda-capabilities or supportedCudaCapabilities)
        ) buildConfig.kernel
      );
      stdenv =
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkgs.stdenv
        else if oldLinuxCompat then
          pkgs.stdenvGlibc_2_27
        else
          pkgs.cudaPackages.backendStdenv;
    in
    if buildConfig.general.universal then
      # No torch extension sources? Treat it as a noarch package.
      pkgs.callPackage ./torch-extension-noarch ({
        inherit src rev torch;
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
    }:
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
      upstreamBuildSets = builtins.filter (buildSet: buildSet.upstreamVariant) buildSets;
      extensions = buildDistTorchExtensions {
        inherit path rev;
        buildSets = upstreamBuildSets;
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
    { path, rev, extraPythonPackages ? [] }:
    let
      buildConfig = readBuildConfig path;
      # Get extra Python packages from build.toml or parameter
      configExtraPackages = buildConfig.test.python-packages or [];
      configGitPackages = buildConfig.test.python-git-packages or [];
      allExtraPackages = extraPythonPackages ++ configExtraPackages;
      
      shellForBuildSet =
        { path, rev }:
        buildSet: {
          name = torchBuildVersion buildSet;
          value =
            with buildSet.pkgs;
            let
              # Function to resolve regular nixpkgs packages
              resolvePythonPackage = name:
                if builtins.hasAttr name python3.pkgs
                then python3.pkgs.${name}
                else throw "Python package '${name}' not found in nixpkgs";
              
              # Function to build packages from Git URLs
              buildGitPackage = spec:
                let
                  # Parse the spec - can be just URL or { url = "..."; ref = "..."; sha256 = "..."; }
                  gitSpec = if builtins.isString spec then { url = spec; } else spec;
                  gitUrl = gitSpec.url;
                  gitRef = gitSpec.ref or "main";
                  gitRev = gitSpec.rev or null;
                  packageName = gitSpec.name or (builtins.baseNameOf (lib.removeSuffix ".git" gitUrl));
                  
                  # Require sha256 for Git packages to work in pure evaluation mode
                  gitSrc = if gitSpec ? sha256 then
                    if gitRev != null then
                      fetchgit {
                        url = gitUrl;
                        rev = gitRev;
                        sha256 = gitSpec.sha256;
                      }
                    else
                      # fetchgit doesn't support 'ref', so we need to resolve the ref to a rev first
                      # For now, we'll require users to use 'rev' instead of 'ref' with fetchgit
                      throw ''
                        Git package "${packageName}" uses 'ref' but fetchgit requires 'rev'.
                        
                        To fix this, get the commit hash for the ref and use 'rev' instead:
                        
                        # Get the commit hash for the tag/branch:
                        git ls-remote ${gitUrl} ${gitRef}
                        
                        # Or use nix-prefetch-git with the commit hash:
                        nix-prefetch-git --url ${gitUrl} --rev <commit-hash-from-above>
                        
                        Then update your build.toml to use 'rev' instead of 'ref':
                        python-git-packages = [
                          { url = "${gitUrl}", rev = "<commit-hash>", sha256 = "${gitSpec.sha256}" }
                        ]
                      ''
                  else
                    throw ''
                      Git package "${packageName}" is missing required sha256 hash.
                      
                      To fix this:
                      
                      1. Get the commit hash for your ref:
                         git ls-remote ${gitUrl} ${if gitRev != null then gitRev else gitRef}
                      
                      2. Get the sha256 hash:
                         nix-prefetch-git --url ${gitUrl} --rev <commit-hash-from-step-1>
                      
                      3. Update your build.toml:
                         python-git-packages = [
                           { url = "${gitUrl}", rev = "<commit-hash>", sha256 = "<hash-from-step-2>" }
                         ]
                    '';
                in
                python3.pkgs.buildPythonPackage {
                  pname = packageName;
                  version = if gitRev != null then "git-${lib.substring 0 7 gitRev}" else "git-${gitRef}";
                  src = gitSrc;
                  
                  # Use setuptools format for maximum compatibility
                  format = "setuptools";
                  
                  # Basic build dependencies
                  nativeBuildInputs = with python3.pkgs; [
                    setuptools
                    wheel
                  ];
                  
                  # Allow builds to fail gracefully during development
                  doCheck = false;
                  
                  meta = {
                    description = "Python package from Git: ${gitUrl}";
                    homepage = gitUrl;
                  };
                };
              
              # Resolve all regular packages
              extraPackages = map resolvePythonPackage allExtraPackages;
              
              # Build all Git packages
              gitPackages = map buildGitPackage configGitPackages;
              
              # Combine all packages
              allPackages = extraPackages ++ gitPackages;
            in
            mkShell {
              buildInputs = [
                (python3.withPackages (
                  ps: with ps; [
                    buildSet.torch
                    pytest
                  ] ++ allPackages
                ))
              ];
              shellHook = ''
                export PYTHONPATH=${buildTorchExtension buildSet { inherit path rev; }}
              '';
            };
        };
      filteredBuildSets = applicableBuildSets buildConfig buildSets;
    in
    builtins.listToAttrs (lib.map (shellForBuildSet { inherit path rev; }) filteredBuildSets);

  torchDevShells =
    { path, rev }:
    let
      shellForBuildSet =
        buildSet:
        let
          pkgs = buildSet.pkgs;
          rocmSupport = pkgs.config.rocmSupport or false;
          stdenv = if rocmSupport then pkgs.stdenv else pkgs.cudaPackages.backendStdenv;
          mkShell = pkgs.mkShell.override { inherit stdenv; };
        in
        {
          name = torchBuildVersion buildSet;
          value = mkShell {
            nativeBuildInputs = with pkgs; [
              build2cmake
              kernel-abi-check
            ];
            buildInputs = with pkgs; [ python3.pkgs.pytest ];
            inputsFrom = [ (buildTorchExtension buildSet { inherit path rev; }) ];
            env = lib.optionalAttrs rocmSupport {
              PYTORCH_ROCM_ARCH = lib.concatStringsSep ";" buildSet.torch.rocmArchs;
              HIP_PATH = pkgs.rocmPackages.clr;
            };
          };
        };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map shellForBuildSet filteredBuildSets);
}
