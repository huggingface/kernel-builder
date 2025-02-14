{ pkgs }:

let
  builder = pkgs.callPackage ./builder.nix {};
in {
  cutlass_2_10 = builder {
    version = "2.10.0";
    hash = "sha256-e2SwXNNwjl/1fV64b+mOJvwGDYeO1LFcqZGbNten37U=";
  };

  cutlass_3_5 = builder {
    version = "3.5.1";
    hash = "sha256-sTGYN+bjtEqQ7Ootr/wvx3P9f8MCDSSj3qyCWjfdLEA=";
  };

  cutlass_3_6 = builder {
    version = "3.6.0";
    hash = "sha256-FbMVqR4eZyum5w4Dj5qJgBPOS66sTem/qKZjYIK/7sg=";
  };
}
