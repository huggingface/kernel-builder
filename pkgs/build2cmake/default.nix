{
  lib,
  rustPlatform,
}:

let
  version = (builtins.fromTOML (builtins.readFile ../../build2cmake/Cargo.toml)).package.version;
in
rustPlatform.buildRustPackage {
  inherit version;
  pname = "build2cmake";

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
