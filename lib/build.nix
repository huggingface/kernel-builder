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
  nameToPath = path: name: path + "/${name}";
  torchBuildVersion = import ./build-version.nix;
in
rec {
  resolveDeps = import ./deps.nix { inherit lib; };

  readToml = path: builtins.fromTOML (builtins.readFile path);

  readBuildConfig = path: readToml (path + "/build.toml");

  hashSrcs =
    srcs:
    let
      # Convert fileset to a list of paths
      filesList = lib.filesystem.listFilesRecursive srcs;
      hashSrc = file: builtins.readFile file;
    in
    builtins.hashString "sha256" (builtins.concatStringsSep "" (map hashSrc filesList));

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
        || (buildSet.gpu == "rocm" && languages'.cuda-hipify);
    in
    builtins.filter supportedBuildSet buildSets;

    getSourceHash = 
      path:
      let
        # Use the first buildSet configuration for hashing
        buildSet = builtins.head buildSets;
        inherit (lib) fileset;
        buildConfig = readBuildConfig path;
        kernels = buildConfig.kernel or { };
        extraDeps = resolveDeps {
          pkgs = buildSet.pkgs;
          torch = buildSet.torch;
          deps = lib.unique (lib.flatten (lib.mapAttrsToList (_: buildConfig: buildConfig.depends) kernels));
        };
        extConfig = buildConfig.torch;
        pyExt =
          extConfig.pyext or [
            "py"
            "pyi"
          ];
        pyFilter = file: builtins.any (ext: file.hasExt ext) pyExt;
        extSrc = extConfig.src or [ ] ++ [ "build.toml" ];
        pySrcSet = fileset.fileFilter pyFilter (path + "/torch-ext");
        kernelsSrc = fileset.unions (
          lib.flatten (lib.mapAttrsToList (name: buildConfig: map (nameToPath path) buildConfig.src) kernels)
        );
        srcSet = fileset.unions (map (nameToPath path) extSrc);
        src = fileset.toSource {
          root = path;
          fileset = fileset.unions [
            kernelsSrc
            srcSet
            pySrcSet
          ];
        };
        srcHash = builtins.substring 0 7 (hashSrcs src);
      in
        # Print the hash and create a derivation with the hash
        builtins.trace "Source Hash = ${srcHash}" (
          buildSet.pkgs.writeTextFile {
            name = "source-hash";
            text = srcHash;
          }
        );

  # Build a single Torch extension.
  buildTorchExtension =
    {
      gpu,
      pkgs,
      torch,
    }:
    {
      path,
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
      extConfig = buildConfig.torch;
      pyExt =
        extConfig.pyext or [
          "py"
          "pyi"
        ];
      pyFilter = file: builtins.any (ext: file.hasExt ext) pyExt;
      extSrc = extConfig.src or [ ] ++ [ "build.toml" ];
      pySrcSet = fileset.fileFilter pyFilter (path + "/torch-ext");
      kernelsSrc = fileset.unions (
        lib.flatten (lib.mapAttrsToList (name: buildConfig: map (nameToPath path) buildConfig.src) kernels)
      );
      srcSet = fileset.unions (map (nameToPath path) extSrc);
      src = fileset.toSource {
        root = path;
        fileset = fileset.unions [
          kernelsSrc
          srcSet
          pySrcSet
        ];
      };
      srcHash = builtins.substring 0 7 (hashSrcs src);

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
        srcHash = srcHash;
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
          ;
        extensionName = buildConfig.general.name;
        srcHash = srcHash;
      });

  # Build multiple Torch extensions.
  buildNixTorchExtensions =
    path:
    let
      extensionForTorch = path: buildSet: {
        name = torchBuildVersion buildSet;
        value = buildTorchExtension buildSet { inherit path; };
      };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch path) filteredBuildSets);

  # Build multiple Torch extensions.
  buildDistTorchExtensions =
    path:
    let
      extensionForTorch = path: buildSet: {
        name = torchBuildVersion buildSet;
        value = buildTorchExtension buildSet {
          inherit path;
          stripRPath = true;
          oldLinuxCompat = true;
        };
      };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (extensionForTorch path) filteredBuildSets);

  buildTorchExtensionBundle =
    path:
    let
      # We just need to get any nixpkgs for use by the path join.
      pkgs = (builtins.head buildSets).pkgs;
      extensions = buildDistTorchExtensions path;
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
    path:
    let
      shellForBuildSet = path: buildSet: {
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
              export PYTHONPATH=${buildTorchExtension buildSet { inherit path; }}
            '';
          };
      };
      filteredBuildSets = applicableBuildSets (readBuildConfig path) buildSets;
    in
    builtins.listToAttrs (lib.map (shellForBuildSet path) filteredBuildSets);
}
