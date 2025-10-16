cmake_minimum_required(VERSION 3.26)

# Set Intel SYCL compiler before project() call
find_program(ICX_COMPILER icx)
find_program(ICPX_COMPILER icpx)
if(ICX_COMPILER AND ICPX_COMPILER)
    execute_process(
      COMMAND ${ICPX_COMPILER} --version
      OUTPUT_VARIABLE ICPX_VERSION_OUTPUT
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(REGEX MATCH "[0-9]+\\.[0-9]+" DPCPP_VERSION "${ICPX_VERSION_OUTPUT}")
    set(DPCPP_VERSION "${DPCPP_VERSION}" CACHE STRING "DPCPP major.minor version")
    set(CMAKE_C_COMPILER ${ICX_COMPILER})
    set(CMAKE_CXX_COMPILER ${ICPX_COMPILER})
    message(STATUS "Using Intel SYCL C++ compiler: ${ICPX_COMPILER} and C compiler: ${ICX_COMPILER} Version: ${DPCPP_VERSION}")
else()
    message(FATAL_ERROR "Intel SYCL C++ compiler (icpx) and/or C compiler (icx) not found. Please install Intel oneAPI toolkit.")
endif()

project({{ name }})

include(FetchContent)
file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}) # Ensure the directory exists
message(STATUS "FetchContent base directory: ${FETCHCONTENT_BASE_DIR}")

include("cmake/utils.cmake")

# Find Python with all necessary components for building extensions
find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Module Development.SABIModule)

append_cmake_prefix_path("torch" "torch.utils.cmake_prefix_path")

find_package(Torch REQUIRED)

# Intel XPU backend detection and setup
if(NOT TORCH_VERSION)
  run_python(TORCH_VERSION "import torch; print(torch.__version__)" "Failed to get Torch version")
endif()

# Check for Intel XPU support in PyTorch
run_python(XPU_AVAILABLE
  "import torch; print('true' if hasattr(torch, 'xpu') else 'false')"
  "Failed to check XPU availability")

if(NOT XPU_AVAILABLE STREQUAL "true")
  message(WARNING "Intel XPU is not available in this PyTorch installation. XPU kernels will be skipped.")
  return()
endif()

# Set up XPU compilation flags
set(GPU_LANG "SYCL")
add_compile_definitions(XPU_KERNEL)
add_compile_definitions(USE_XPU)

# Set SYCL-specific flags
# Set comprehensive SYCL compilation and linking flags
set(sycl_link_flags "-fsycl;--offload-compress;-fsycl-targets=spir64_gen,spir64;-Xs;-device pvc,xe-lpg,ats-m150 -options ' -cl-intel-enable-auto-large-GRF-mode -cl-poison-unsupported-fp64-kernels -cl-intel-greater-than-4GB-buffer-required';")
set(sycl_flags "-fsycl;-fhonor-nans;-fhonor-infinities;-fno-associative-math;-fno-approx-func;-fno-sycl-instrument-device-code;--offload-compress;-fsycl-targets=spir64_gen,spir64;")
message(STATUS "Configuring for Intel XPU backend using SYCL")

# Generate standardized build name
run_python(TORCH_VERSION "import torch; print(torch.__version__.split('+')[0])" "Failed to get Torch version")
run_python(CXX11_ABI_VALUE "import torch; print('TRUE' if torch._C._GLIBCXX_USE_CXX11_ABI else 'FALSE')" "Failed to get CXX11 ABI")
run_python(XPU_VERSION "import torch; print(torch.xpu.get_device_capability['version'].split('+')[0])" "Failed to get XPU version")
cmake_host_system_information(RESULT HOST_ARCH QUERY OS_PLATFORM)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(SYSTEM_STRING "${HOST_ARCH}-linux")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
  set(SYSTEM_STRING "${HOST_ARCH}-windows")
else()
  set(SYSTEM_STRING "${HOST_ARCH}-${CMAKE_SYSTEM_NAME}")
endif()

generate_build_name(BUILD_VARIANT_NAME "${TORCH_VERSION}" ${CXX11_ABI_VALUE} "xpu" "${XPU_VERSION}" "${SYSTEM_STRING}")
