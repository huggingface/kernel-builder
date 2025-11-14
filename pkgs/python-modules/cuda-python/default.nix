{
  buildPythonPackage,
  fetchFromGitHub,

  pythonRelaxDepsHook,
  setuptools,

  cuda-bindings,
  cuda-pathfinder,
}:

buildPythonPackage rec {
  pname = "cuda-python";
  version = "13.0.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-python";
    rev = "v${version}";
    hash = "sha256-Uq1oQWtilocQPh6cZ3P/L/L6caCHv17u1y67sm5fhhA=";
  };

  sourceRoot = "source/cuda_python";

  nativeBuildInputs = [
    pythonRelaxDepsHook
  ];

  build-system = [ setuptools ];

  dependencies = [
    cuda-bindings
    cuda-pathfinder
  ];

  pythonRelaxDeps = [ "cuda-bindings" ];
}
