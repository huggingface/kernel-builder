{
  stdenv,
  extensionName,
  rev,

  # Whether to run get-kernel-check.
  doGetKernelCheck ? true,

  lib,
  build2cmake,
  get-kernel-check,
  torch,

  src,
}:

stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit src;

  # Add Torch as a dependency, so that devshells for universal kernels
  # also get torch as a build input.
  buildInputs = [ torch ];

  nativeBuildInputs =
    [
      build2cmake
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
    cp -r torch-ext/${extensionName} $out/
  '';

  doInstallCheck = true;

  getKernelCheck = extensionName;
})
