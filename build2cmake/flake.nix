{
  description = "A very basic flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {

        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              cargo
              clippy
              openssl.dev
              pkg-config
              rustc
              rustfmt
              rust-analyzer
            ];

            RUST_SRC_PATH = "${rustPlatform.rustLibSrc}";
          };
      }
    );
}
