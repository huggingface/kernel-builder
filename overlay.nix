final: prev: {
  blas = prev.blas.override { blasProvider = prev.mkl; };

  lapack = prev.lapack.override { lapackProvider = prev.mkl; };

  magma-cuda-static = prev.magma-cuda-static.overrideAttrs (
    _: prevAttrs: { buildInputs = prevAttrs.buildInputs ++ [ (prev.lib.getLib prev.gfortran.cc) ]; }
  );

  cutlass = prev.callPackage ./pkgs/cutlass { };

  cmakeNvccThreadsHook = prev.callPackage ./pkgs/cmake-nvcc-threads-hook { };

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      python-self: python-super: with python-self; {
        torch_2_4 = callPackage ./pkgs/python-modules/torch_2_4 {
          inherit (prev.darwin.apple_sdk.frameworks) Accelerate CoreServices;
          inherit (prev.darwin) libobjc;
        };

        torch_2_5 = callPackage ./pkgs/python-modules/torch_2_5 { };
      }
    )
  ];

  stdenvGlibc_2_27 = prev.callPackage ./pkgs/stdenv-glibc-2_27 { };
}
