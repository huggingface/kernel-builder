{
  lib,
  stdenv,

  build2cmake,
  get-kernel-check,
  kernel-layout-check,
  remove-bytecode-hook,
  torch,
}:

{
  # Whether to run get-kernel-check.
  doGetKernelCheck ? true,

  kernelName,

  # Revision to bake into the ops name.
  rev,

  src,
}:

let
  moduleName = builtins.replaceStrings [ "-" ] [ "_" ] kernelName;
in

stdenv.mkDerivation (prevAttrs: {
  name = "${kernelName}-torch-ext";

  inherit moduleName src;

  # Add Torch as a dependency, so that devshells for universal kernels
  # also get torch as a build input.
  buildInputs = [ torch ];

  nativeBuildInputs = [
    build2cmake
    kernel-layout-check
    remove-bytecode-hook
  ]
  ++ lib.optionals doGetKernelCheck [
    get-kernel-check
  ];

  dontBuild = true;

  # We do not strictly need this, since we don't use the setuptools-based
  # build. But `build2cmake` does proper validation of the build.toml, so
  # we run it anyway.
  postPatch = ''
    build2cmake generate-torch --ops-id ${rev} build.toml
  '';

  installPhase = ''
    mkdir -p $out
    cp -r torch-ext/${moduleName}/* $out/
    mkdir $out/${moduleName}
    cp ${./compat.py} $out/${moduleName}/__init__.py
  '';

  doInstallCheck = true;
})
