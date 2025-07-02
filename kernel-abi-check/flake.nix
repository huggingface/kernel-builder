{
  description = "kernel-abi-check devenv";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://huggingface.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "huggingface.cachix.org-1:ynTPbLS0W8ofXd9fDjk1KvoFky9K2jhxe6r4nXAkc/o="
    ];
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      rust-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "rust-analyzer"
            "rust-src"
          ];
        };
      in
      {

        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              openssl.dev
              pkg-config
              rust
            ];

            RUST_SRC_PATH = "${rust}/lib/rustlib/src/rust/library";
          };
      }
    );
}
