{ lib }:

{
  flattenVersion = version: lib.replaceStrings [ "." ] [ "" ] (lib.versions.pad 2 version);
  abiString = cxx11Abi: if cxx11Abi then "cxx11" else "cxx98";
}
