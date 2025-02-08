{
  stdenv,
  wrapCCWith,
  bintools,
  glibc,
  llvm,
  rocm-device-libs,
  rsync,
}:

wrapCCWith {
  inherit bintools;

  cc = stdenv.mkDerivation {
    inherit (llvm) version;
    pname = "romc-llvm-clang-unwrapped";

    nativeBuildInputs = [ rsync ];

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      for path in ${llvm}/llvm ${bintools}; do
        rsync -a $path/ $out/
      done
      chmod -R u+w $out

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

  nixSupport.cc-cflags = [
    "-fuse-ld=lld"
    "--rocm-device-lib-path=${rocm-device-libs}/amdgcn/bitcode"
    "-rtlib=compiler-rt"
    "-unwindlib=libunwind"
    "-Wno-unused-command-line-argument"
  ];

  extraBuildCommands = ''
    echo "" > $out/nix-support/add-hardening.sh

    # GPU compilation uses builtin `lld`
    substituteInPlace $out/bin/{clang,clang++} \
      --replace-fail "-MM) dontLink=1 ;;" "-MM | --cuda-device-only) dontLink=1 ;;''\n--cuda-host-only | --cuda-compile-host-device) dontLink=0 ;;"
  '';
}
