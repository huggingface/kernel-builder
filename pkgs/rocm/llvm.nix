{ stdenv, wrapBintoolsWith, wrapCCWith, glibc }:
final: prev:
let
  llvm = final.rocm-llvm;
  bintools-unwrapped = final.callPackage ./bintools-unwrapped.nix {
    inherit llvm;
  };
  bintools = wrapBintoolsWith {
    bintools = bintools-unwrapped;
    libc = glibc;
  };
  clang = final.callPackage ./clang.nix { inherit bintools llvm; };
in {
  llvm = {
    inherit bintools-unwrapped;
    inherit bintools;
    inherit clang;
  };
}
