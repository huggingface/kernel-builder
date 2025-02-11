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

  # List of components from the runfile.
  components,
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

  src = callPackage ./runfile.nix { };

  # Avoid expensive copy of the whole bundle on each build.
  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    rsync
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    stdenv.cc.cc.libgcc
  ] ++ (map (dep: rocmPackages.${dep}) filteredDeps);

  installPhase = ''
    mkdir $out
    for bundleSrc in ${lib.concatStringsSep " " components}; do
      rsync -a ${src}/component-rocm/$bundleSrc/content/opt/rocm-${version}/* $out/
    done
  '';

  autoPatchelfIgnoreMissingDeps = [
    # Not sure where this comes from, not in the distribution.
    "amdpythonlib.so"

    # Should come from the driver runpath.
    "libOpenCL.so.1"

    # Distribution only has libamdhip64.so.6? Only seems to be used
    # by /bin/roofline-* for older Linux distributions.
    "libamdhip64.so.5"

    # Python 3.8 is not in nixpkgs anymore.
    "libpython3.8.so.1.0"
  ];
}
