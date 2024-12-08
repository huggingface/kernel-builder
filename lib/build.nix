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

  # Build a single kernel.
  buildKernel =
    {
      name,
      path,
      buildConfig,
      pkgs,
      torch,
    }:
    let
      src = builtins.path {
        inherit path;
        name = "${name}-src";
        filter = srcFilter buildConfig.src;
      };
      cudaCapabilities = lib.intersectLists pkgs.cudaPackages.flags.cudaCapabilities buildConfig.capabilities;
    in
    pkgs.callPackage ./kernel {
      inherit cudaCapabilities src;
      kernelName = name;
      kernelSources = buildConfig.src;
      kernelDeps = resolveDeps {
        inherit pkgs torch;
        deps = buildConfig.depends;
      };
    };

  # Build all kernels defined in build.toml.
  buildKernels =
    {
      path,
      pkgs,
      torch,
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
    }:
    let
      buildConfig = readBuildConfig path;
      extConfig = buildConfig.torch;
      src = builtins.path {
        inherit path;
        name = "${extConfig.name}-src";
        filter = srcFilter (extConfig.src ++ extConfig.pysrc);
      };
    in
    pkgs.callPackage ./torch-extension {
      inherit src stripRPath torch;
      extensionName = extConfig.name;
      extensionSources = extConfig.src;
      extensionVersion = buildConfig.general.version;
      pySources = extConfig.pysrc;
      kernels = buildKernels { inherit path pkgs torch; };
    };

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
}
