{ system }:

final: prev:

let
  glibc_2_27 = (import (builtins.fetchGit {
      # Descriptive name to make the store path easier to identify
      name = "my-old-revision";
      url = "https://github.com/NixOS/nixpkgs/";
      ref = "refs/heads/nixpkgs-unstable";
         rev = "a9eb3eed170fa916e0a8364e5227ee661af76fde";
  }) { inherit system; }).glibc;
  stdenvWithGlibc = glibc: stdenv:
    let
      compilerWrapped = prev.wrapCCWith {
        cc = prev.gcc;
        bintools = prev.wrapBintoolsWith {
          bintools = prev.binutils-unwrapped;
          libc = glibc;
        };
      };
    in prev.overrideCC stdenv compilerWrapped;
in 

{
  blas = prev.blas.override { blasProvider = prev.mkl; };

  lapack = prev.lapack.override { lapackProvider = prev.mkl; };

  magma-cuda-static = prev.magma-cuda-static.overrideAttrs (
    _: prevAttrs: { buildInputs = prevAttrs.buildInputs ++ [ (prev.lib.getLib prev.gfortran.cc) ]; }
  );

  cutlass = prev.callPackage ./pkgs/cutlass { };

  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      python-self: python-super: with python-self; {
        torch_2_4 = callPackage ./pkgs/python-modules/torch_2_4 {
          inherit (prev.darwin.apple_sdk.frameworks) Accelerate CoreServices;
          inherit (prev.darwin) libobjc;
        };

        torch_2_5 = callPackage ./pkgs/python-modules/torch_2_5 { };
      }
    )
  ];

  stdenvGlibc_2_27 = stdenvWithGlibc glibc_2_27 prev.stdenv;
}
