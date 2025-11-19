final: prev: {
  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  # Local packages

  build2cmake = prev.callPackage ./pkgs/build2cmake { };

  get-kernel-check = prev.callPackage ./pkgs/get-kernel-check { };

  kernel-abi-check = prev.callPackage ./pkgs/kernel-abi-check { };

  kernel-layout-check = prev.callPackage ./pkgs/kernel-layout-check { };

  rewrite-nix-paths-macho = prev.callPackage ./pkgs/rewrite-nix-paths-macho { };

  remove-bytecode-hook = prev.callPackage ./pkgs/remove-bytecode-hook { };

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };

  # Python packages
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      python-self: python-super: with python-self; {
        cuda-bindings = python-self.callPackage ./pkgs/python-modules/cuda-bindings { };

        cuda-pathfinder = python-self.callPackage ./pkgs/python-modules/cuda-pathfinder { };

        # Starting with the CUDA 12.8 version, cuda-python is a metapackage
        # that pulls in relevant dependencies. For CUDA 12.6 it is just
        # cuda-bindings.
        cuda-python =
          if final.cudaPackages.cudaMajorMinorVersion == "12.6" then
            python-self.cuda-bindings
          else
            python-self.callPackage ./pkgs/python-modules/cuda-python { };

        nvidia-cutlass-dsl = python-self.callPackage ./pkgs/python-modules/nvidia-cutlass-dsl { };

        kernel-abi-check = callPackage ./pkgs/python-modules/kernel-abi-check { };

        kernels = python-super.kernels.overrideAttrs (oldAttrs: {
          version = "unstable";

          src = final.fetchFromGitHub {
            owner = "huggingface";
            repo = "kernels";
            rev = "0e18dbf076fc44de5dac4027616e9f3d9e2da45a";
            sha256 = "sha256-6N1W3jLQIS1yEAdNR2X9CuFdMw4Ia0yzBBVQ4Kujv8U=";
          };
        });

        pyclibrary = python-self.callPackage ./pkgs/python-modules/pyclibrary { };

        mkTorch = callPackage ./pkgs/python-modules/torch/binary { };

        torch-bin_2_8 = mkTorch {
          version = "2.8";
          xpuPackages = final.xpuPackages_2025_1;
        };

        torch-bin_2_9 = mkTorch {
          version = "2.9";
          xpuPackages = final.xpuPackages_2025_2;
        };

        torch_2_8 = callPackage ./pkgs/python-modules/torch/source/2_8 {
          xpuPackages = final.xpuPackages_2025_1;
        };

        torch_2_9 = callPackage ./pkgs/python-modules/torch/source/2_9 {
          xpuPackages = final.xpuPackages_2025_2;
        };
      }
    )
  ];
}
