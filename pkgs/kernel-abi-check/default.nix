{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "kernel-abi-check";
  version = "0.0.1";

  src =
    let
      sourceFiles = file: file.name == "Cargo.toml" || file.name == "Cargo.lock" || file.hasExt "rs";
    in
    lib.fileset.toSource {
      root = ../../kernel-abi-check;
      fileset = lib.fileset.fileFilter sourceFiles ../../kernel-abi-check;
    };

  cargoLock = {
    lockFile = ../../kernel-abi-check/Cargo.lock;
  };

  setupHook = ./kernel-abi-check-hook.sh;

  meta = {
    description = "Check glibc and libstdc++ ABI compat";
  };
}
