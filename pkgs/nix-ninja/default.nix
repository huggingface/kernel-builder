{
  fetchFromGitHub,
  rustPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nix-ninja";
  version = "unstable-2025-09-17";

  src = /home/daniel/git/nix-ninja;

  src' = fetchFromGitHub {
    owner = "pdtpartners";
    repo = "nix-ninja";
    rev = "8da02bd560f8bb406b82ae17ca99375f2b841b12";
    hash = "sha256-yzI9lfWHeFkqm0/uA0uMIHW+mqGqk5jhT58dfVMO+dk=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) src;
    hash = "sha256-h/2DSt0bgCJsZZM31im4dN2knxFJzfpv6JQbgFupIGg=";
  };

  nativeBuildInputs = [ rustPlatform.cargoSetupHook ];
})
