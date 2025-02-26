final: prev:
{
  blas = prev.blas.override { blasProvider = prev.mkl; };

  lapack = prev.lapack.override { lapackProvider = prev.mkl; };

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

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };

  build2cmake = prev.callPackage ./pkgs/build2cmake { };
}
// (import ./pkgs/cutlass { pkgs = final; })
