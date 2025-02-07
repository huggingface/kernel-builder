{
  runCommand,
  llvm,
}:

runCommand "rocm-llvm-lld-${llvm.version}" ''
  mkdir -p $out/bin
  ln -s ${llvm}/llvm/bin/lld
''

callPackage ../base.nix rec {
  inherit stdenv;
  buildMan = false; # No man pages to build
  targetName = "lld";
  targetDir = targetName;
  extraBuildInputs = [ llvm ];
  checkTargets = [ "check-${targetName}" ];
}
