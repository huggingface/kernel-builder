{
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
}:

buildPythonPackage rec {
  pname = "cuda-pathfinder";
  version = "1.3.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-python";
    rev = "${pname}-v${version}";
    hash = "sha256-hm/LoOVpJVKkOuKrBdHnYi1JMCNeB2ozAvz/N6RG0zU=";
  };

  sourceRoot = "source/cuda_pathfinder";

  build-system = [ setuptools ];

  pythonImportsCheck = [ "cuda.pathfinder" ];
}
