final: prev: {
  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  # Local packages

  build2cmake = prev.callPackage ./pkgs/build2cmake { };

  get-kernel-check = prev.callPackage ./pkgs/get-kernel-check { };

  kernel-abi-check = prev.callPackage ./pkgs/kernel-abi-check { };

  rewrite-nix-paths-macho = prev.callPackage ./pkgs/rewrite-nix-paths-macho { };

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };

  # Python packages
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      python-self: python-super: with python-self; {
        kernel-abi-check = callPackage ./pkgs/python-modules/kernel-abi-check { };

        kernels = python-super.kernels.overrideAttrs (oldAttrs: {
          version = "unstable";

          src = final.fetchFromGitHub {
            owner = "huggingface";
            repo = "kernels";
            rev = "5d21b86a5d611100c10c10b79ffa7965edf567fd";
            sha256 = "sha256-lKQUVbjhpeXKj1SeZRxgPSsOtBUZ7zQeO6pRoA1h+W8=";
          };
        });
      }
    )
  ];
}
