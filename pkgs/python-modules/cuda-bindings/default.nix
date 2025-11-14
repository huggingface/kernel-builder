{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  symlinkJoin,

  autoAddDriverRunpath,
  cython,
  pyclibrary,
  setuptools,

  cuda-pathfinder,
  cudaPackages,
  versioneer,
}:
let
  outpaths =
    with cudaPackages;
    [
      cuda_cudart
      cuda_nvcc
      cuda_nvrtc
      cuda_profiler_api
      libcufile
    ]
    ++ lib.optionals (cudaAtLeast "13.0") [ cuda_crt ];

  cudatoolkit_joined = symlinkJoin {
    name = "cudatoolkit-joined-${cudaPackages.cudaMajorMinorVersion}";
    paths =
      outpaths ++ lib.concatMap (outpath: lib.map (output: outpath.${output}) outpath.outputs) outpaths;
  };

  versionHashes = {
    "12.6" = {
      version = "12.6.2.post1";
      hash = "sha256-MG6q+Hyo0H4XKZLbtFQqfen6T2gxWzyk1M9jWryjjj4=";
    };
    "12.8" = {
      version = "12.8.0";
      hash = "sha256-7e9w70KkC6Pcvyu6Cwt5Asrc3W9TgsjiGvArRTer6Oc=";
    };
    "12.9" = {
      version = "12.9.4";
      hash = "sha256-eqdBBlcfuVCFNl0osKV4lfH0QjWxdyThTDLhEFZrPKM=";
    };
    "13.0" = {
      version = "13.0.3";
      hash = "sha256-Uq1oQWtilocQPh6cZ3P/L/L6caCHv17u1y67sm5fhhA=";
    };
  };

  versionHash =
    versionHashes.${cudaPackages.cudaMajorMinorVersion}
      or (throw "Unsupported CUDA version: ${cudaPackages.cudaMajorMinorVersion}");
  inherit (versionHash) hash version;

in
buildPythonPackage {
  pname = "cuda-bindings";
  inherit version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-python";
    rev = "v${version}";
    inherit hash;
  };

  sourceRoot = "source/cuda_bindings";

  build-system = [
    cython
    pyclibrary
    setuptools
    versioneer
  ];

  dependencies = [ cuda-pathfinder ];

  nativeBuildInputs = [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
  ];

  env.CUDA_HOME = cudatoolkit_joined;

  pythonImportsCheck = [ "cuda.bindings" ];
}
