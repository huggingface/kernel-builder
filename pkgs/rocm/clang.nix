{
  stdenv,
  wrapCCWith,
  bintools,
  glibc,
  llvm,
}:

wrapCCWith {
  inherit bintools;

  cc = stdenv.mkDerivation {
    inherit (llvm) version;
    pname = "romc-llvm-clang-unwrapped";

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      for path in ${llvm}/llvm ${bintools}; do
        cp -a $path/* $out/
        chmod -R u+w $out
      done
      #for prog in ${llvm}/llvm/bin/*; do
      #  echo $prog
      #  echo $(basename $prog)
      #  ln -sf $prog $out/bin/$(basename $prog)
      #done

      runHook postInstall
    '';

    passthru = {
      isClang = true;
      isROCm = true;
    };
  };

  gccForLibs = stdenv.cc.cc;

  extraPackages = [
    bintools
    glibc
  ];
}
