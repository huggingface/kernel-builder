final: prev:
{
  # Overrides

  blas = if final.stdenv.isx86_64 then prev.blas.override { blasProvider = prev.mkl; } else prev.blas;

  lapack =
    if final.stdenv.isx86_64 then prev.lapack.override { lapackProvider = prev.mkl; } else prev.blas;

  magma-cuda-static = prev.magma-cuda-static.overrideAttrs (
    _: prevAttrs: { buildInputs = prevAttrs.buildInputs ++ [ (prev.lib.getLib prev.gfortran.cc) ]; }
  );

  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  magma-hip =
    (prev.callPackage ./pkgs/magma {
      cudaSupport = false;
      rocmSupport = true;
    }).magma;

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      python-self: python-super: with python-self; {
        torch_2_5 = callPackage ./pkgs/python-modules/torch_2_5 { };

        torch_2_6 = callPackage ./pkgs/python-modules/torch_2_6 { rocmPackages = final.rocmPackages; };
      }
    )
  ];

  # Local packages

  kernel-abi-check = prev.callPackage ./pkgs/kernel-abi-check { };

  build2cmake = prev.callPackage ./pkgs/build2cmake { };

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };
}
// (import ./pkgs/cutlass { pkgs = final; })
