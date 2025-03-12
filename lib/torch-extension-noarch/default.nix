{
  stdenv,
  extensionName,

  src,
}:

stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit src;

  installPhase = ''
    mkdir -p $out
    cp -r torch-ext/${extensionName} $out/
  '';
})
