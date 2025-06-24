final: prev: {
  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  # Local packages

  kernel-abi-check = prev.callPackage ./pkgs/kernel-abi-check { };

  build2cmake = prev.callPackage ./pkgs/build2cmake { };

  rewrite-nix-paths-macho = prev.callPackage ./pkgs/rewrite-nix-paths-macho { };

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };
}
