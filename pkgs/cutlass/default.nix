{
  lib,
  fetchFromGitHub,
  cmake,
  cudaPackages,
  python3,
}:

cudaPackages.backendStdenv.mkDerivation rec {
  pname = "cutlass";
  version = "3.5.1";

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-sTGYN+bjtEqQ7Ootr/wvx3P9f8MCDSSj3qyCWjfdLEA=";
  };

  nativeBuildInputs =
    [ cmake ]
    ++ (with cudaPackages; [
      setupCudaHook
      cuda_nvcc
    ]);

  buildInputs = [ python3 ] ++ (with cudaPackages; [ cuda_cudart ]);

  cmakeFlags = [
    (lib.cmakeBool "CUTLASS_ENABLE_GTEST_UNIT_TESTS" false)
    (lib.cmakeBool "CUTLASS_ENABLE_HEADERS_ONLY" true)
  ];

  meta = {
    description = "CUDA Templates for Linear Algebra Subroutines";
    homepage = "https://github.com/NVIDIA/cutlass";
    license = lib.licenses.bsd3;
  };
}
