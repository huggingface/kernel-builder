{
  stdenv,
  extensionName,
  rev,

  build2cmake,

  src,
}:

stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit src;

  nativeBuildInputs = [ build2cmake ];

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
})
