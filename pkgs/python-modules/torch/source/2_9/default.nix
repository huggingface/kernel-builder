{
  stdenv,
  stdenvAdapters,
  lib,
  fetchFromGitHub,
  fetchpatch,
  buildPythonPackage,
  python,
  config,
  cudaSupport ? config.cudaSupport,
  cudaPackages,
  autoAddDriverRunpath,
  effectiveMagma ?
    if cudaSupport then
      magma-cuda-static
    else if rocmSupport then
      magma-hip
    else
      magma,
  effectiveStdenv ? if cudaSupport then cudaPackages.backendStdenv else stdenv,
  magma,
  magma-hip,
  magma-cuda-static,
  # Use the system NCCL as long as we're targeting CUDA on a supported platform.
  useSystemNccl ? (cudaSupport && !cudaPackages.nccl.meta.unsupported || rocmSupport),
  MPISupport ? false,
  mpi,
  nvtx,
  buildDocs ? false,
  cxx11Abi ? true,

  # tests.cudaAvailable:
  callPackage,

  # Native build inputs
  cmake,
  symlinkJoin,
  which,
  pybind11,
  removeReferencesTo,

  # Build inputs
  apple-sdk_15,
  libdrm,
  numactl,

  # dependencies
  astunparse,
  binutils,
  expecttest,
  filelock,
  fsspec,
  hypothesis,
  jinja2,
  networkx,
  packaging,
  psutil,
  pyyaml,
  requests,
  setuptools,
  sympy,
  types-dataclasses,
  typing-extensions,
  # ROCm build and `torch.compile` requires `triton`
  tritonSupport ? (!stdenv.hostPlatform.isDarwin),
  triton,

  # TODO: 1. callPackage needs to learn to distinguish between the task
  #          of "asking for an attribute from the parent scope" and
  #          the task of "exposing a formal parameter in .override".
  # TODO: 2. We should probably abandon attributes such as `torchWithCuda` (etc.)
  #          as they routinely end up consuming the wrong arguments\
  #          (dependencies without cuda support).
  #          Instead we should rely on overlays and nixpkgsFun.
  # (@SomeoneSerge)
  _tritonEffective ?
    if cudaSupport then
      triton-cuda
    else if xpuSupport then
      python.pkgs.triton-xpu_2_9
    else
      triton,
  triton-cuda,

  # Disable MKLDNN on aarch64-darwin, it negatively impacts performance,
  # this is also what official pytorch build does
  mklDnnSupport ? !(stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64),

  # virtual pkg that consistently instantiates blas across nixpkgs
  # See https://github.com/NixOS/nixpkgs/pull/83888
  blas,

  # ninja (https://ninja-build.org) must be available to run C++ extensions tests,
  ninja,

  # dependencies for torch.utils.tensorboard
  pillow,
  six,
  tensorboard,
  protobuf,

  # ROCm dependencies
  rocmSupport ? config.rocmSupport,
  rocmPackages,
  xpuSupport ? (config.xpuSupport or false),
  xpuPackages,
  gpuTargets ? [ ],
}:

let
  inherit (lib)
    attrsets
    lists
    strings
    trivial
    ;
  inherit (cudaPackages) cudnn nccl;
  cudaFlags = cudaPackages.flags;

  triton = throw "python3Packages.torch: use _tritonEffective instead of triton to avoid divergence";

  setBool = v: if v then "1" else "0";

  archs = (import ../../archs.nix)."2.9";

  supportedTorchCudaCapabilities =
    let
      inherit (archs) capsPerCudaVersion;
      real = capsPerCudaVersion."${lib.versions.majorMinor cudaPackages.cudaMajorMinorVersion}";
      ptx = lists.map (x: "${x}+PTX") real;
    in
    real ++ ptx;

  inherit (archs) supportedTorchRocmArchs;

  # NOTE: The lists.subtractLists function is perhaps a bit unintuitive. It subtracts the elements
  #   of the first list *from* the second list. That means:
  #   lists.subtractLists a b = b - a

  # For CUDA
  supportedCudaCapabilities = lists.intersectLists cudaFlags.cudaCapabilities supportedTorchCudaCapabilities;
  unsupportedCudaCapabilities = lists.subtractLists supportedCudaCapabilities cudaFlags.cudaCapabilities;

  # Use trivial.warnIf to print a warning if any unsupported GPU targets are specified.
  gpuArchWarner =
    supported: unsupported:
    trivial.throwIf (supported == [ ]) (
      "No supported GPU targets specified. Requested GPU targets: "
      + strings.concatStringsSep ", " unsupported
    ) supported;

  # Create the gpuTargetString.
  gpuTargetString = strings.concatStringsSep ";" (
    if gpuTargets != [ ] then
      # If gpuTargets is specified, it always takes priority.
      gpuTargets
    else if cudaSupport then
      gpuArchWarner supportedCudaCapabilities unsupportedCudaCapabilities
    else if rocmSupport then
      supportedTorchRocmArchs
    else
      throw "No GPU targets specified"
  );

  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    paths = with rocmPackages; [
      aotriton_0_11
      clr
      comgr
      hipblas
      hipblas-common-devel
      hipblaslt
      hipfft
      hipify-clang
      hiprand
      hipsolver
      hipsparse
      hipsparselt
      hsa-rocr
      miopen-hip
      rccl
      rocblas
      rocm-core
      rocm-device-libs
      rocm-hip-runtime
      rocm-smi-lib
      rocminfo
      rocrand
      rocsolver
      rocsparse
      roctracer
    ];

    postBuild = ''
      # Fix `setuptools` not being found
      rm -rf $out/nix-support

      # Variables that we want to pass through to downstream derivations.
      mkdir -p $out/nix-support
      echo 'export ROCM_PATH="${placeholder "out"}"' >> $out/nix-support/setup-hook
      echo 'export ROCM_SOURCE_DIR="${placeholder "out"}"' >> $out/nix-support/setup-hook
      echo 'export CMAKE_CXX_FLAGS="-I${placeholder "out"}/include -I${placeholder "out"}/include/rocblas"' >> $out/nix-support/setup-hook
    '';
  };

  brokenConditions = attrsets.filterAttrs (_: cond: cond) {
    "CUDA and ROCm are mutually exclusive" = cudaSupport && rocmSupport;
    "CUDA is not targeting Linux" = cudaSupport && !stdenv.hostPlatform.isLinux;
    "Unsupported CUDA version" =
      cudaSupport
      && !(builtins.elem cudaPackages.cudaMajorVersion [
        "12"
        "13"
      ]);
    "MPI cudatoolkit does not match cudaPackages.cudatoolkit" =
      MPISupport && cudaSupport && (mpi.cudatoolkit != cudaPackages.cudatoolkit);
    # This used to be a deep package set comparison between cudaPackages and
    # effectiveMagma.cudaPackages, making torch too strict in cudaPackages.
    # In particular, this triggered warnings from cuda's `aliases.nix`
    "Magma cudaPackages does not match cudaPackages" =
      cudaSupport
      && (effectiveMagma.cudaPackages.cudaMajorMinorVersion != cudaPackages.cudaMajorMinorVersion);
    #"Rocm support is currently broken because `rocmPackages.hipblaslt` is unpackaged. (2024-06-09)" =
    #  rocmSupport;
  };
  torchXpuOpsSrc =
    if xpuSupport then
      fetchFromGitHub {
        owner = "intel";
        repo = "torch-xpu-ops";
        rev = "f8408a642da568051ab82e20f2947b89e491fbeb";
        hash = "sha256-eoT8mvaPw1NFFTYFVT6NUqOFOo4rDdNrIseF+FDpXUk=";
      }
    else
      null;
in
buildPythonPackage rec {
  pname = "torch";
  version = "2.9.0";
  pyproject = true;

  stdenv = effectiveStdenv;

  outputs = [
    "out" # output standard python package
    "dev" # output libtorch headers
    "lib" # output libtorch libraries
    "cxxdev" # propagated deps for the cmake consumers of torch
  ];
  cudaPropagateToOutput = "cxxdev";
  rocmPropagateToOutput = "cxxdev";

  src = fetchFromGitHub {
    owner = "pytorch";
    repo = "pytorch";
    tag = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-Jszhe67FteiSbkbUEjVIkWVUjUY8IS5qVHct4HvcfIg=";
  };

  patches = [
    ./mkl-rpath.patch
  ]
  ++ lib.optionals cudaSupport [ ./fix-cmake-cuda-toolkit.patch ]
  ++ lib.optionals (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64) [
    # pthreadpool added support for Grand Central Dispatch in April
    # 2020. However, this relies on functionality (DISPATCH_APPLY_AUTO)
    # that is available starting with macOS 10.13. However, our current
    # base is 10.12. Until we upgrade, we can fall back on the older
    # pthread support.
    ./pthreadpool-disable-gcd.diff
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # Propagate CUPTI to Kineto by overriding the search path with environment variables.
    # https://github.com/pytorch/pytorch/pull/108847
    ./pytorch-pr-108847.patch
  ];

  postUnpack = lib.optionalString xpuSupport ''
    cp -r --no-preserve=mode ${torchXpuOpsSrc} $sourceRoot/third_party/torch-xpu-ops
    patch -d $sourceRoot/third_party/torch-xpu-ops -p1 < ${./0001-patch-xpu-ops-CMake.patch}
  '';

  postPatch =
    let
      pyiGenPath = "${typing-extensions}/${python.sitePackages}:${pyyaml}/${python.sitePackages}";
    in
    ''
      substituteInPlace pyproject.toml \
        --replace-fail "setuptools>=70.1.0,<80.0" \
                       "setuptools>=70.1.0"

      substituteInPlace cmake/public/cuda.cmake \
        --replace-fail \
          'message(FATAL_ERROR "Found two conflicting CUDA' \
          'message(WARNING "Found two conflicting CUDA' \
        --replace-warn \
          "set(CUDAToolkit_ROOT" \
          "# Upstream: set(CUDAToolkit_ROOT"
      substituteInPlace third_party/gloo/cmake/Cuda.cmake \
        --replace-warn "find_package(CUDAToolkit 7.0" "find_package(CUDAToolkit"

      # annotations (3.7), print_function (3.0), with_statement (2.6) are all supported
      sed -i -e "/from __future__ import/d" **.py
      #substituteInPlace third_party/NNPACK/CMakeLists.txt \
      #  --replace-fail "PYTHONPATH=" 'PYTHONPATH=$ENV{PYTHONPATH}:'
      # flag from cmakeFlags doesn't work, not clear why
      # setting it at the top of NNPACK's own CMakeLists does
      sed -i '2s;^;set(PYTHON_SIX_SOURCE_DIR ${six.src})\n;' third_party/NNPACK/CMakeLists.txt

      # Ensure that torch profiler unwind uses addr2line from nix
      substituteInPlace torch/csrc/profiler/unwind/unwind.cpp \
        --replace-fail 'addr2line_binary_ = "addr2line"' 'addr2line_binary_ = "${lib.getExe' binutils "addr2line"}"'

      # gen_pyi needs typing-extensions.
      #substituteInPlace torch/CMakeLists.txt \
      #  --replace-fail "env PYTHONPATH=\"\''${TORCH_ROOT}\"" \
      #                 "env PYTHONPATH=\"\''${TORCH_ROOT}:${pyiGenPath}\""
    ''
    + lib.optionalString rocmSupport ''
      # https://github.com/facebookincubator/gloo/pull/297
      substituteInPlace third_party/gloo/cmake/Hipify.cmake \
        --replace-fail "\''${HIPIFY_COMMAND}" "python \''${HIPIFY_COMMAND}"

      # Replace hard-coded rocm paths
      substituteInPlace caffe2/CMakeLists.txt \
        --replace-fail "/opt/rocm" "${rocmtoolkit_joined}"
    ''
    # Detection of NCCL version doesn't work particularly well when using the static binary.
    + lib.optionalString cudaSupport ''
      substituteInPlace cmake/Modules/FindNCCL.cmake \
        --replace-fail \
          'message(FATAL_ERROR "Found NCCL header version and library version' \
          'message(WARNING "Found NCCL header version and library version'
    ''
    # Remove PyTorch's FindCUDAToolkit.cmake and use CMake's default.
    # NOTE: Parts of pytorch rely on unmaintained FindCUDA.cmake with custom patches to support e.g.
    # newer architectures (sm_90a). We do want to delete vendored patches, but have to keep them
    # until https://github.com/pytorch/pytorch/issues/76082 is addressed
    + lib.optionalString cudaSupport ''
      rm cmake/Modules/FindCUDAToolkit.cmake
    ''
    + lib.optionalString xpuSupport ''
      # replace oneapi DIR
      substituteInPlace cmake/Modules/FindMKL.cmake \
        --replace-fail 'SET(DEFAULT_INTEL_ONEAPI_DIR "/opt/intel/oneapi")' 'SET(DEFAULT_INTEL_ONEAPI_DIR ${xpuPackages.oneapi-torch-dev}/oneapi)'
      # replace mkldnn build for xpu
      sed -i '/ExternalProject_Add(xpu_mkldnn_proj/,/^ *)/s/^/#/' cmake/Modules/FindMKLDNN.cmake
      substituteInPlace cmake/Modules/FindMKLDNN.cmake \
        --replace-fail 'ExternalProject_Get_Property(xpu_mkldnn_proj SOURCE_DIR BINARY_DIR)' '# ExternalProject_Get_Property(xpu_mkldnn_proj SOURCE_DIR BINARY_DIR)' \
        --replace-fail  "set(XPU_MKLDNN_LIBRARIES \''${BINARY_DIR}/src/\''${DNNL_LIB_NAME})" "set(XPU_MKLDNN_LIBRARIES ${xpuPackages.onednn-xpu}/lib/libdnnl.a)" \
        --replace-fail  "set(XPU_MKLDNN_INCLUDE \''${SOURCE_DIR}/include \''${BINARY_DIR}/include)" "set(XPU_MKLDNN_INCLUDE ${xpuPackages.onednn-xpu}/include)"
      # comment torch-xpu-ops git clone block in pytorch/caffe2/CMakeLists.txt
      sed -i '/set(TORCH_XPU_OPS_REPO_URL/,/^  endif()/s/^/#/' caffe2/CMakeLists.txt
      sed -i '/execute_process(/,/^  endif()/s/^/#/' caffe2/CMakeLists.txt
    ''
    # error: no member named 'aligned_alloc' in the global namespace; did you mean simply 'aligned_alloc'
    # This lib overrided aligned_alloc hence the error message. Tltr: his function is linkable but not in header.
    +
      lib.optionalString
        (stdenv.hostPlatform.isDarwin && lib.versionOlder stdenv.hostPlatform.darwinSdkVersion "11.0")
        ''
          substituteInPlace third_party/pocketfft/pocketfft_hdronly.h --replace-fail '#if (__cplusplus >= 201703L) && (!defined(__MINGW32__)) && (!defined(_MSC_VER))
          inline void *aligned_alloc(size_t align, size_t size)' '#if 0
          inline void *aligned_alloc(size_t align, size_t size)'
        '';

  # NOTE(@connorbaker): Though we do not disable Gloo or MPI when building with CUDA support, caution should be taken
  # when using the different backends. Gloo's GPU support isn't great, and MPI and CUDA can't be used at the same time
  # without extreme care to ensure they don't lock each other out of shared resources.
  # For more, see https://github.com/open-mpi/ompi/issues/7733#issuecomment-629806195.
  preConfigure =
    lib.optionalString cudaSupport ''
      export TORCH_CUDA_ARCH_LIST="${gpuTargetString}"
      export CUPTI_INCLUDE_DIR=${lib.getDev cudaPackages.cuda_cupti}/include
      export CUPTI_LIBRARY_DIR=${lib.getLib cudaPackages.cuda_cupti}/lib
    ''
    + lib.optionalString (cudaSupport && cudaPackages ? cudnn) ''
      export CUDNN_INCLUDE_DIR=${lib.getLib cudnn}/include
      export CUDNN_LIB_DIR=${cudnn.lib}/lib
    ''
    + lib.optionalString rocmSupport ''
      export PYTORCH_ROCM_ARCH="${gpuTargetString}"
      python tools/amd_build/build_amd.py
    '';

  # Use pytorch's custom configurations
  dontUseCmakeConfigure = true;

  # causes possible redefinition of _FORTIFY_SOURCE
  hardeningDisable = [ "fortify3" ];

  BUILD_NAMEDTENSOR = setBool true;
  BUILD_DOCS = setBool buildDocs;

  # We only do an imports check, so do not build tests either.
  BUILD_TEST = setBool false;

  # ninja hook doesn't automatically turn on ninja
  # because pytorch setup.py is responsible for this
  CMAKE_GENERATOR = "Ninja";

  # Whether to use C++11 ABI (or earlier).
  _GLIBCXX_USE_CXX11_ABI = setBool cxx11Abi;

  # Unlike MKL, oneDNN (née MKLDNN) is FOSS, so we enable support for
  # it by default. PyTorch currently uses its own vendored version
  # of oneDNN through Intel iDeep.
  USE_MKLDNN = setBool mklDnnSupport;
  USE_MKLDNN_CBLAS = setBool mklDnnSupport;

  # Avoid using pybind11 from git submodule
  # Also avoids pytorch exporting the headers of pybind11
  USE_SYSTEM_PYBIND11 = true;

  cmakeFlags = [
    # (lib.cmakeBool "CMAKE_FIND_DEBUG_MODE" true)
    (lib.cmakeFeature "CUDAToolkit_VERSION" cudaPackages.cudaMajorMinorVersion)
  ]
  ++ lib.optionals cudaSupport [
    # Unbreaks version discovery in enable_language(CUDA) when wrapping nvcc with ccache
    # Cf. https://gitlab.kitware.com/cmake/cmake/-/issues/26363
    (lib.cmakeFeature "CMAKE_CUDA_COMPILER_TOOLKIT_VERSION" cudaPackages.cudaMajorMinorVersion)
  ];

  preBuild = ''
    export MAX_JOBS=$NIX_BUILD_CORES
    ${python.pythonOnBuildForHost.interpreter} setup.py build --cmake-only
    ${cmake}/bin/cmake build
  '';

  preFixup = ''
    function join_by { local IFS="$1"; shift; echo "$*"; }
    function strip2 {
      IFS=':'
      read -ra RP <<< $(patchelf --print-rpath $1)
      IFS=' '
      RP_NEW=$(join_by : ''${RP[@]:2})
      patchelf --set-rpath \$ORIGIN:''${RP_NEW} "$1"
    }
    for f in $(find ''${out} -name 'libcaffe2*.so')
    do
      strip2 $f
    done
  '';

  # Override the (weirdly) wrong version set by default. See
  # https://github.com/NixOS/nixpkgs/pull/52437#issuecomment-449718038
  # https://github.com/pytorch/pytorch/blob/v1.0.0/setup.py#L267
  PYTORCH_BUILD_VERSION = version;
  PYTORCH_BUILD_NUMBER = 0;

  # In-tree builds of NCCL are not supported.
  # Use NCCL when cudaSupport is enabled and nccl is available.
  USE_NCCL = setBool useSystemNccl;
  USE_SYSTEM_NCCL = USE_NCCL;
  USE_STATIC_NCCL = USE_NCCL;

  # Set the correct Python library path, broken since
  # https://github.com/pytorch/pytorch/commit/3d617333e
  PYTHON_LIB_REL_PATH = "${placeholder "out"}/${python.sitePackages}";

  # Suppress a weird warning in mkl-dnn, part of ideep in pytorch
  # (upstream seems to have fixed this in the wrong place?)
  # https://github.com/intel/mkl-dnn/commit/8134d346cdb7fe1695a2aa55771071d455fae0bc
  # https://github.com/pytorch/pytorch/issues/22346
  #
  # Also of interest: pytorch ignores CXXFLAGS uses CFLAGS for both C and C++:
  # https://github.com/pytorch/pytorch/blob/v1.11.0/setup.py#L17
  env = {
    # Builds faster without this and we don't have enough inputs that cmd length is an issue
    NIX_CC_USE_RESPONSE_FILE = 0;

    NIX_CFLAGS_COMPILE = toString (
      (lib.optionals (blas.implementation == "mkl") [ "-Wno-error=array-bounds" ] ++ [ "-Wno-error" ])
    );
  }
  // lib.optionalAttrs rocmSupport {
    AOTRITON_INSTALLED_PREFIX = rocmPackages.aotriton_0_10;
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    USE_MPS = 1;
  }
  // lib.optionalAttrs xpuSupport {
    MKLROOT = xpuPackages.oneapi-torch-dev;
    SYCL_ROOT = xpuPackages.oneapi-torch-dev;
  };

  nativeBuildInputs = [
    cmake
    ninja
    pybind11
    removeReferencesTo
    which
  ]
  ++ lib.optionals cudaSupport (
    with cudaPackages;
    [
      autoAddDriverRunpath
      cuda_nvcc
    ]
  )
  ++ lib.optionals rocmSupport [
    rocmtoolkit_joined
    rocmPackages.setupRocmHook
  ]
  ++ lib.optionals xpuSupport (
    with xpuPackages;
    [
      ocloc
      oneapi-torch-dev
    ]
  );

  buildInputs = [
    blas
    blas.provider
  ]
  ++ lib.optionals cudaSupport (
    with cudaPackages;
    [
      cuda_cccl # <thrust/*>
      cuda_cudart # cuda_runtime.h and libraries
      cuda_cupti # For kineto
      cuda_nvcc # crt/host_config.h; even though we include this in nativeBuildInputs, it's needed here too
      cuda_nvml_dev # <nvml.h>
      cuda_nvrtc
      #cuda_nvtx # -llibNVToolsExt
      cuda_profiler_api # <cuda_profiler_api.h>
      nvtx
      libcublas
      libcufile
      libcufft
      libcurand
      libcusolver
      libcusparse
    ]
    ++ lists.optionals (cudaPackages ? cudnn) [ cudnn ]
    ++ lists.optionals useSystemNccl [
      # Some platforms do not support NCCL (i.e., Jetson)
      nccl # Provides nccl.h AND a static copy of NCCL!
    ]
  )
  ++ lib.optionals rocmSupport (
    with rocmPackages;
    [
      composablekernel-devel
      hipcub-devel
      libdrm
      openmp
      rocmtoolkit_joined
      rocprim-devel
      rocthrust-devel
    ]
  )
  ++ lib.optionals xpuSupport (
    with xpuPackages;
    [
      oneapi-torch-dev
      onednn-xpu
    ]
  )
  ++ lib.optionals (cudaSupport || rocmSupport) [ effectiveMagma ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ numactl ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
  ]
  ++ lib.optionals tritonSupport [ _tritonEffective ]
  ++ lib.optionals MPISupport [ mpi ];

  pythonRelaxDeps = [
    "sympy"
  ];
  dependencies = [
    astunparse
    expecttest
    filelock
    fsspec
    hypothesis
    jinja2
    networkx
    ninja
    packaging
    psutil
    pyyaml
    requests
    sympy
    types-dataclasses
    typing-extensions

    # the following are required for tensorboard support
    pillow
    six
    tensorboard
    protobuf

    # torch/csrc requires `pybind11` at runtime
    pybind11
  ]
  ++ lib.optionals (lib.versionAtLeast python.version "3.12") [ setuptools ]
  ++ lib.optionals tritonSupport [ _tritonEffective ];

  propagatedCxxBuildInputs =
    [ ] ++ lib.optionals MPISupport [ mpi ] ++ lib.optionals rocmSupport [ rocmtoolkit_joined ];

  # Tests take a long time and may be flaky, so just sanity-check imports
  doCheck = false;

  pythonImportsCheck = [ "torch" ];

  nativeCheckInputs = [
    hypothesis
    ninja
    psutil
  ];

  checkPhase =
    with lib.versions;
    with lib.strings;
    concatStringsSep " " [
      "runHook preCheck"
      "${python.interpreter} test/run_test.py"
      "--exclude"
      (concatStringsSep " " [
        "utils" # utils requires git, which is not allowed in the check phase

        # "dataloader" # psutils correctly finds and triggers multiprocessing, but is too sandboxed to run -- resulting in numerous errors
        # ^^^^^^^^^^^^ NOTE: while test_dataloader does return errors, these are acceptable errors and do not interfere with the build

        # tensorboard has acceptable failures for pytorch 1.3.x due to dependencies on tensorboard-plugins
        (optionalString (majorMinor version == "1.3") "tensorboard")
      ])
      "runHook postCheck"
    ];

  pythonRemoveDeps = [
    # In our dist-info the name is just "triton"
    "pytorch-triton-rocm"
  ];

  postInstall = ''
    find "$out/${python.sitePackages}/torch/include" "$out/${python.sitePackages}/torch/lib" -type f -exec remove-references-to -t ${effectiveStdenv.cc} '{}' +

    mkdir $dev
    cp -r $out/${python.sitePackages}/torch/include $dev/include
    cp -r $out/${python.sitePackages}/torch/share $dev/share

    # Fix up library paths for split outputs
    substituteInPlace \
      $dev/share/cmake/Torch/TorchConfig.cmake \
      --replace-fail \''${TORCH_INSTALL_PREFIX}/lib "$lib/lib"

    substituteInPlace \
      $dev/share/cmake/Caffe2/Caffe2Targets-release.cmake \
      --replace-fail \''${_IMPORT_PREFIX}/lib "$lib/lib"

    mkdir $lib
    mv $out/${python.sitePackages}/torch/lib $lib/lib
    ln -s $lib/lib $out/${python.sitePackages}/torch/lib
  ''
  + lib.optionalString rocmSupport ''
    substituteInPlace $dev/share/cmake/Tensorpipe/TensorpipeTargets-release.cmake \
      --replace-fail "\''${_IMPORT_PREFIX}/lib64" "$lib/lib"

    substituteInPlace $dev/share/cmake/ATen/ATenConfig.cmake \
      --replace-fail "/build/source/torch/include" "$dev/include"
  '';

  postFixup = ''
    mkdir -p "$cxxdev/nix-support"
    printWords "''${propagatedCxxBuildInputs[@]}" >> "$cxxdev/nix-support/propagated-build-inputs"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    for f in $(ls $lib/lib/*.dylib); do
        install_name_tool -id $lib/lib/$(basename $f) $f || true
    done

    install_name_tool -change @rpath/libshm.dylib $lib/lib/libshm.dylib $lib/lib/libtorch_python.dylib
    install_name_tool -change @rpath/libtorch.dylib $lib/lib/libtorch.dylib $lib/lib/libtorch_python.dylib
    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libtorch_python.dylib

    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libtorch.dylib

    install_name_tool -change @rpath/libtorch.dylib $lib/lib/libtorch.dylib $lib/lib/libshm.dylib
    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libshm.dylib
  '';

  # See https://github.com/NixOS/nixpkgs/issues/296179
  #
  # This is a quick hack to add `libnvrtc` to the runpath so that torch can find
  # it when it is needed at runtime.
  extraRunpaths = lib.optionals cudaSupport [ "${lib.getLib cudaPackages.cuda_nvrtc}/lib" ];
  postPhases = lib.optionals stdenv.hostPlatform.isLinux [ "postPatchelfPhase" ];
  postPatchelfPhase = ''
    while IFS= read -r -d $'\0' elf ; do
      for extra in $extraRunpaths ; do
        echo patchelf "$elf" --add-rpath "$extra" >&2
        patchelf "$elf" --add-rpath "$extra"
      done
    done < <(
      find "''${!outputLib}" "$out" -type f -iname '*.so' -print0
    )
  '';

  # Builds in 2+h with 2 cores, and ~15m with a big-parallel builder.
  requiredSystemFeatures = [ "big-parallel" ];

  passthru = {
    inherit
      cudaSupport
      cudaPackages
      cxx11Abi
      rocmSupport
      rocmPackages
      xpuSupport
      xpuPackages
      ;
    cudaCapabilities = if cudaSupport then supportedCudaCapabilities else [ ];
    rocmArchs = if rocmSupport then supportedTorchRocmArchs else [ ];
    # At least for 1.10.2 `torch.fft` is unavailable unless BLAS provider is MKL. This attribute allows for easy detection of its availability.
    blasProvider = blas.provider;
    # To help debug when a package is broken due to CUDA support
    inherit brokenConditions;
    tests = callPackage ./tests.nix { };
  };

  meta = {
    changelog = "https://github.com/pytorch/pytorch/releases/tag/v${version}";
    # keep PyTorch in the description so the package can be found under that name on search.nixos.org
    description = "PyTorch: Tensors and Dynamic neural networks in Python with strong GPU acceleration";
    homepage = "https://pytorch.org/";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [
      teh
      thoughtpolice
      tscholak
    ]; # tscholak esp. for darwin-related builds
    platforms =
      lib.platforms.linux ++ lib.optionals (!cudaSupport && !rocmSupport) lib.platforms.darwin;
    broken = builtins.any trivial.id (builtins.attrValues brokenConditions);
  };
}
