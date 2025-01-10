{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "toml2cmake";
  version = "0.0.1";

  src =  let
  sourceFiles = file: file.name == "Cargo.toml" || file.name == "Cargo.lock" || file.name == "pyproject.toml" || file.hasExt "rs" || file.hasExt "cmake" || file.hasExt "py";
  in lib.fileset.toSource {
    root = ../../toml2cmake;
    fileset = lib.fileset.fileFilter sourceFiles ../../toml2cmake;
  };

  cargoLock = {
    lockFile = ../../toml2cmake/Cargo.lock;
  };

  meta = {
    description = "Create cmake build infrastructure from build.toml files";
  };
}
