{
  fetchFromGitHub,
  overrideCC,
  system,
  wrapBintoolsWith,
  wrapCCWith,
  stdenv,
  bintools-unwrapped,
  cudaPackages,
  libgcc,
}:

let
  nixpkgs_20191230 = import (fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "a9eb3eed170fa916e0a8364e5227ee661af76fde";
    hash = "sha256-1ycrr9HMrGA3ZDM8qmKcZICBupE5UShnIIhPRWdvAzA=";
  }) { inherit system; };

  glibc_2_27 = nixpkgs_20191230.glibc.overrideAttrs (prevAttrs: {
    # Slight adjustments for compatibility with modern nixpkgs:
    #
    # - pname is required
    # - an additional getent output
    # - passthru libgcc

    pname = "glibc";

    outputs = prevAttrs.outputs ++ [ "getent" ];

    postInstall =
      prevAttrs.postInstall
      + ''
        install -Dm755 $bin/bin/getent -t $getent/bin
      '';

    passthru = prevAttrs.passthru // {
      # Should be stdenv's gcc, but we don't have access to it.
      libgcc = libgcc;
    };
  });

  gcc_8_3 = nixpkgs_20191230.gcc;

  stdenvWith =
    newGlibc: newLibcxx: newGcc: stdenv:
    let
      # We need gcc to have a libgcc that is compatible with glibc. We
      # do this in three steps to avoid an infinite recursion: (1) we
      # create an stdenv with gcc and glibc; (2) we rebuild glibc using
      # this stdenv, so that we have a libgcc that is compatible with
      # glibc; (3) we create the final stdenv that contains the compatible
      # gcc + glibc.
      onlyGlibc = overrideCC stdenv (wrapCCWith {
        cc = newGcc;
        bintools = wrapBintoolsWith {
          bintools = bintools-unwrapped;
          libc = newGlibc;
        };
      });
      compilerWrapped = wrapCCWith {
        cc = newGcc.override { stdenv = onlyGlibc; };
        bintools = wrapBintoolsWith {
          bintools = bintools-unwrapped;
          libc = newGlibc;
        };
        libcxx = newLibcxx;
      };
    in
    overrideCC stdenv compilerWrapped;

in
stdenvWith glibc_2_27 gcc_8_3.cc.lib cudaPackages.backendStdenv.cc.cc stdenv
