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

  # Build a single kernel.
  buildKernel =
    {
      name,
      path,
      buildConfig,
      pkgs,
      torch,

      oldLinuxCompat ? false,
    }:
    let
      src' = builtins.path {
        inherit path;
        name = "${name}-src";
        filter = srcFilter buildConfig.src;
      };
      srcSet = lib.fileset.unions (map (nameToPath path) buildConfig.src);
      src = lib.fileset.toSource {
        root = path;
        fileset = srcSet;
      };
      cudaCapabilities = lib.intersectLists pkgs.cudaPackages.flags.cudaCapabilities buildConfig.capabilities;
    in
    pkgs.callPackage ./kernel (
      {
        inherit cudaCapabilities src;
        kernelName = name;
        kernelSources = buildConfig.src;
        kernelDeps = resolveDeps {
          inherit pkgs torch;
          deps = buildConfig.depends;
        };
        kernelInclude = buildConfig.include or [ ];
        nvccThreads = builtins.length cudaCapabilities;
      }
      // (lib.optionalAttrs oldLinuxCompat {
        stdenv = pkgs.stdenvGlibc_2_27;
      })
    );

  # Build all kernels defined in build.toml.
  buildKernels =
    {
      path,
      pkgs,
      torch,
      oldLinuxCompat ? false,
    }:
    let
      buildConfig = readBuildConfig path;
      kernels = lib.mapAttrs (
        name: buildConfig:
        buildKernel {
          inherit
            name
            path
            buildConfig
            pkgs
            torch
            oldLinuxCompat
            ;
        }
      ) buildConfig.kernel;
    in
    kernels;

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
      buildConfig = readBuildConfig path;
      extConfig = buildConfig.torch;
      pyExt = extConfig.pyext or [ "py" "pyi" ];
      pyFilter = file: builtins.any (ext: file.hasExt ext) pyExt;
      srcSet = lib.fileset.unions (map (nameToPath path) extConfig.src);
      src = lib.fileset.toSource {
        root = path;
        fileset = srcSet;
      };
      pySrcSet = lib.fileset.fileFilter pyFilter (path + "/${extConfig.pyroot}");
      pySrc = lib.fileset.toSource {
        root = path + "/${extConfig.pyroot}";
        fileset = pySrcSet;
      };
    in
    pkgs.callPackage ./torch-extension (
      {
        inherit
          pySrc
          src
          stripRPath
          torch
          ;
        extensionName = extConfig.name;
        extensionSources = extConfig.src;
        extensionVersion = buildConfig.general.version;
        extensionInclude = extConfig.include or [ ];
        kernels = buildKernels {
          inherit
            oldLinuxCompat
            path
            pkgs
            torch
            ;
        };
      }
      // (lib.optionalAttrs oldLinuxCompat {
        stdenv = pkgs.stdenvGlibc_2_27;
      })
    );

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
