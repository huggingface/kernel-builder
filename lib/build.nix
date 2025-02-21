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

  srcFilter =
    src: name: type:
    type == "directory" || lib.any (suffix: lib.hasSuffix suffix name) src;

  # Build a single Torch extension.
  buildTorchExtension =
    {
      path,
      pkgs,
      torch,
      stripRPath ? false,
      oldLinuxCompat ? false,
    }:
    let
      inherit (lib) fileset;
      buildConfig = readBuildConfig path;
      extraDeps = resolveDeps {
        inherit pkgs torch;
        deps = lib.unique (
          lib.flatten (lib.mapAttrsToList (_: buildConfig: buildConfig.depends) buildConfig.kernel)
        );
      };
      extConfig = buildConfig.torch;
      pyExt =
        extConfig.pyext or [
          "py"
          "pyi"
        ];
      pyFilter = file: builtins.any (ext: file.hasExt ext) pyExt;
      extSrc = extConfig.src ++ [ "build.toml" ];
      pySrcSet = fileset.fileFilter pyFilter (path + "/torch-ext");
      kernelsSrc = fileset.unions (
        lib.flatten (
          lib.mapAttrsToList (name: buildConfig: map (nameToPath path) buildConfig.src) buildConfig.kernel
        )
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

      # Set number of threads to the largest number of capabilities.
      listMax = lib.foldl' lib.max 1;
      nvccThreads = listMax (
        lib.mapAttrsToList (
          _: buildConfig: builtins.length buildConfig.cuda-capabilities
        ) buildConfig.kernel
      );
      stdenv = if oldLinuxCompat then pkgs.stdenvGlibc_2_27 else pkgs.cudaPackages.backendStdenv;
    in
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
    });

  # Build multiple Torch extensions.
  buildNixTorchExtensions =
    let
      extensionForTorch = path: buildSet: {
        name = torchBuildVersion buildSet;
        value = buildTorchExtension ({ inherit path; } // buildSet);
      };
    in
    path: builtins.listToAttrs (lib.map (extensionForTorch path) buildSets);

  # Build multiple Torch extensions.
  buildDistTorchExtensions =
    let
      extensionForTorch = path: buildSet: {
        name = torchBuildVersion buildSet;
        value = buildTorchExtension (
          {
            inherit path;
            stripRPath = true;
            oldLinuxCompat = true;
          }
          // buildSet
        );
      };
    in
    path: builtins.listToAttrs (lib.map (extensionForTorch path) buildSets);

  buildTorchExtensionBundle =
    path:
    let
      # We just need to get any nixpkgs for use by the path join.
      pkgs = (builtins.head buildSets).pkgs;
      extensions = buildDistTorchExtensions path;
      namePaths = lib.mapAttrs (name: pkg: toString pkg) extensions;
    in
    import ./join-paths {
      inherit pkgs namePaths;
      name = "torch-ext-bundle";
    };

  # Get a development shell with the extension in PYTHONPATH. Handy
  # for running tests.
  torchExtensionShells =
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
              export PYTHONPATH=${buildTorchExtension ({ inherit path; } // buildSet)}
            '';
          };
      };
    in
    path: builtins.listToAttrs (lib.map (shellForBuildSet path) buildSets);
}
