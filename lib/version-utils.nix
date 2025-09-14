{ lib }:

let
  inherit (lib) versions;
in
{
  flattenVersion =
    version: lib.replaceStrings [ "." ] [ "" ] (versions.majorMinor (versions.pad 2 version));
  abiString = cxx11Abi: if cxx11Abi then "cxx11" else "cxx98";
}
