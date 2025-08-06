[
  {
    torchVersion = "2.7";
    cudaVersion = "11.8";
    cxx11Abi = true;
    systems = [ "x86_64-linux" ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.7";
    cudaVersion = "12.6";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.7";
    cudaVersion = "12.8";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.7";
    rocmVersion = "6.3.4";
    cxx11Abi = true;
    systems = [ "x86_64-linux" ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.7";
    cxx11Abi = true;
    metal = true;
    systems = [ "aarch64-darwin" ];
    upstreamVariant = true;
  }

  {
    torchVersion = "2.8";
    cudaVersion = "12.6";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.8";
    cudaVersion = "12.8";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.8";
    cudaVersion = "12.9";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.8";
    rocmVersion = "6.3.4";
    cxx11Abi = true;
    systems = [ "x86_64-linux" ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.8";
    rocmVersion = "6.4.1";
    cxx11Abi = true;
    systems = [ "x86_64-linux" ];
    upstreamVariant = true;
  }
  {
    torchVersion = "2.8";
    cxx11Abi = true;
    metal = true;
    systems = [ "aarch64-darwin" ];
    upstreamVariant = true;
  }

  # Non-standard versions; not included in bundle builds.
  {
    torchVersion = "2.7";
    cudaVersion = "12.9";
    cxx11Abi = true;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  }
]
