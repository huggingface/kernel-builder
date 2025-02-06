{
  autoPatchelfHook,
  callPackage,
  stdenv,

  pname,
}:

stdenv.mkDerivation rec {
  inherit pname;
  version = src.version;

  src = callPackage ./bundle.nix { };

  buildInputs = [
    stdenv.cc.cc.lib
    stdenv.cc.cc.libgcc
  ];

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    mkdir $out
    cp -r ${src}/component-rocm/${pname}/content/opt/rocm-${version}/* $out/
  '';
}
