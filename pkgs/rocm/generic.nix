{
  lib,
  autoPatchelfHook,
  callPackage,
  stdenv,
  rsync,
  rocmPackages,

  pname,

  # List of string-typed dependencies.
  deps,

  # List of source packages in the bundle.
  bundleSrcs,
}:

let
  filteredDeps = lib.filter (
    dep:
    !builtins.elem dep [
      "amdgpu-core"
      "libdrm-amdgpu-common"
      "libdrm-amdgpu-amdgpu1"
      "libdrm-amdgpu-radeon1"
      "libdrm-amdgpu-dev"
      "libdrm2-amdgpu"
    ]
  ) deps;
in
stdenv.mkDerivation rec {
  inherit pname;
  version = src.version;

  src = callPackage ./bundle.nix { };

  nativeBuildInputs = [
    autoPatchelfHook
    rsync
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    stdenv.cc.cc.libgcc
  ] ++ (map (dep: rocmPackages.${dep}) filteredDeps);

  # Avoid expensive copy of the whole bundle on each build.
  dontUnpack = true;

  installPhase = ''
    mkdir $out
    for bundleSrc in ${lib.concatStringsSep " " bundleSrcs}; do
      rsync -a ${src}/component-rocm/$bundleSrc/content/opt/rocm-${version}/* $out/
    done
  '';
}
