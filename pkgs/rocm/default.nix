{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  fetchpatch,
  addDriverRunpath,
  autoPatchelfHook,
  bzip2,
  expat,
  gmp,
  libdrm,
  libva,
  libxcrypt-legacy,
  libxml2,
  libyamlcpp,
  mpfr,
  ncurses,
  pciutils,
  python310,
  rsync,
  numactl,
  xz,
  zlib,
  zstd,
}:

stdenv.mkDerivation rec {
  pname = "rocm";
  version = "6.3.2";

  src = fetchurl {
    name = "rocm-bundle";
    url = "https://repo.radeon.com/rocm/installer/rocm-runfile-installer/rocm-rel-${version}/ubuntu/22.04/rocm-installer_1.0.0.60302-7~22.04.run";

    # Make the extracted runfile a fixed-output derivation. This avoids
    # unpacking the runfile during every build.
    recursiveHash = true;
    downloadToTemp = true;
    hash = "sha256-cB4v8Jfwnuhms5OPp26yg5tF+MY/vrvVK4IFSmcyjkg=";

    postFetch = ''
      SETUP_NOCHECK=1 sh "$downloadedFile" --noexec --target $out
    '';
  };

  nativeBuildInputs = [
    addDriverRunpath
    autoPatchelfHook
  ];

  buildInputs = [
    bzip2
    expat
    gmp
    libdrm
    libva
    libxcrypt-legacy
    libxml2
    (libyamlcpp.overrideAttrs (oldAttrs: rec {
      name = "${oldAttrs.pname}-${version}";
      version = "0.7.0";
      src = fetchFromGitHub {
        owner = "jbeder";
        repo = "yaml-cpp";
        rev = "yaml-cpp-${version}";
        hash = "sha256-2tFWccifn0c2lU/U1WNg2FHrBohjx8CXMllPJCevaNk=";
      };
      patches = [
        # https://github.com/jbeder/yaml-cpp/issues/774
        # https://github.com/jbeder/yaml-cpp/pull/1037
        (fetchpatch {
          name = "yaml-cpp-Fix-generated-cmake-config.patch";
          url = "https://github.com/jbeder/yaml-cpp/commit/4f48727b365962e31451cd91027bd797bc7d2ee7.patch";
          hash = "sha256-jarZAh7NgwL3xXzxijDiAQmC/EC2WYfNMkYHEIQBPhM=";
        })
        # TODO: Remove with the next release, when https://github.com/jbeder/yaml-cpp/pull/1058 is available
        (fetchpatch {
          name = "yaml-cpp-Fix-pc-paths-for-absolute-GNUInstallDirs.patch";
          url = "https://github.com/jbeder/yaml-cpp/commit/328d2d85e833be7cb5a0ab246cc3f5d7e16fc67a.patch";
          hash = "sha256-1M2rxfbVOrRH9kiImcwcEolXOP8DeDW9Cbu03+mB5Yk=";
        })
      ];
    }))
    mpfr
    ncurses
    numactl
    pciutils
    python310
    stdenv.cc.cc.lib
    xz
    zlib
    zstd
  ];

  dontUnpack = true;

  dontBuild = true;

  installPhase = ''
    mkdir "$out"
    # rsync makes this much nicer than cp.
    find ${src} -type d -name rocm-${version} \
      ! -path '*mivisionx*' \
      -exec ${rsync}/bin/rsync -a {}/ $out/ \;
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

  postFixup = ''
    addDriverRunpath $out/bin/clinfo
    addDriverRunpath $out/lib/librocprofiler-sdk.so.*
    addDriverRunpath $out/lib/libhsa-runtime64.so.*
    addDriverRunpath $out/lib/libamd_smi.so.*
    addDriverRunpath $out/share/amd_smi/amdsmi/libamd_smi.so

  '';

  passthru = {
    gpuTargets = lib.forEach [
      "803"
      "900"
      "906"
      "908"
      "90a"
      "940"
      "941"
      "942"
      "1010"
      "1012"
      "1030"
      "1100"
      "1101"
      "1102"
    ] (target: "gfx${target}");
  };

  meta = with stdenv.lib; {
    description = "Software stack for GPU programming";
  };

}
