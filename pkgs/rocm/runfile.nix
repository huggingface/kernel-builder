{
  fetchurl,
}:

let
  version = "6.3.2";
in
fetchurl {
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

  passthru = {
    version = version;
  };
}
