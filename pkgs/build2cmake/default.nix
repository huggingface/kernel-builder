{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "build2cmake";
  version = "0.0.1";

  src =
    let
      sourceFiles =
        file:
        file.name == "Cargo.toml"
        || file.name == "Cargo.lock"
        || file.name == "pyproject.toml"
        || (builtins.any file.hasExt [
          "cmake"
          "h"
          "py"
          "rs"
        ]);
    in
    lib.fileset.toSource {
      root = ../../build2cmake;
      fileset = lib.fileset.fileFilter sourceFiles ../../build2cmake;
    };

  cargoLock = {
    lockFile = ../../build2cmake/Cargo.lock;
  };

  meta = {
    description = "Create cmake build infrastructure from build.toml files";
  };
}
