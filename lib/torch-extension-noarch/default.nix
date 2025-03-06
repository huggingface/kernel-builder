{
  stdenv,
  extensionName,

  src,
}:

stdenv.mkDerivation (prevAttrs: {
  name = "${extensionName}-torch-ext";

  inherit src;

  installPhase = ''
    ls -l 
    mkdir -p $out
    cp -r torch-ext/${extensionName} $out/
  '';
})
