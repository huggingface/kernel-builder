{ system }:

final: prev:

let
  oldNixpkgs = import (builtins.fetchGit {
    name = "nixpkgs-compat";
    url = "https://github.com/NixOS/nixpkgs/";
    ref = "refs/heads/nixpkgs-unstable";
    rev = "a9eb3eed170fa916e0a8364e5227ee661af76fde";
  }) { inherit system; };

  glibc_2_27 = oldNixpkgs.glibc.overrideAttrs (prevAttrs: {
    pname = "glibc";
    outputs = prevAttrs.outputs ++ [ "getent" ];
    # New nixpkgs expect a getent output, but also keep it in
    # glib.bin for compat with old nixpkgs.
    postInstall =
      prevAttrs.postInstall
      + ''
        install -Dm755 $bin/bin/getent -t $getent/bin
      '';

    passthru = prevAttrs.passthru // {
      libgcc = prev.libgcc;
    };
  });

  libcxx = oldNixpkgs.stdenv.cc.cc.lib;

  stdenvWithGlibc =
    glibc: libcxx: gcc: stdenv:
    let
      # We need gcc to have a libgcc that is compatible with glibc. We
      # do this in three steps to avoid an infinite recursion: (1) we
      # create an stdenv with gcc and glibc; (2) we rebuild glibc using
      # this stdenv, so that we have a libgcc that is compatible with
      # glibc; (3) we create the final stdenv that contains the compatible
      # gcc + glibc.
      onlyGlibc = prev.overrideCC stdenv (
        prev.wrapCCWith {
          cc = gcc;
          bintools = prev.wrapBintoolsWith {
            bintools = prev.bintools-unwrapped;
            libc = glibc;
          };
        }
      );
      compilerWrapped = prev.wrapCCWith {
        inherit libcxx;
        cc = gcc.override { stdenv = onlyGlibc; };
        bintools = prev.wrapBintoolsWith {
          bintools = prev.binutils-unwrapped;
          libc = glibc;
        };
      };
    in
    prev.overrideCC stdenv compilerWrapped;
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

  stdenvGlibc_2_27 = stdenvWithGlibc glibc_2_27 libcxx prev.gcc-unwrapped prev.stdenv;
}
