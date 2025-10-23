cmake_minimum_required(VERSION 3.26)
project({{name}} LANGUAGES CXX)

set(TARGET_DEVICE "cuda" CACHE STRING "Target device backend for kernel")

install(CODE "set(CMAKE_INSTALL_LOCAL_ONLY TRUE)" ALL_COMPONENTS)

include(FetchContent)
file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}) # Ensure the directory exists
message(STATUS "FetchContent base directory: ${FETCHCONTENT_BASE_DIR}")

set(CUDA_SUPPORTED_ARCHS "{{ cuda_supported_archs }}")

set(HIP_SUPPORTED_ARCHS "gfx906;gfx908;gfx90a;gfx942;gfx950;gfx1030;gfx1100;gfx1101;gfx1200;gfx1201")

include(${CMAKE_CURRENT_LIST_DIR}/cmake/utils.cmake)

if(DEFINED Python3_EXECUTABLE)
  # Allow passing through the interpreter (e.g. from setup.py).
  find_package(Python3 COMPONENTS Development Development.SABIModule Interpreter)
  if (NOT Python3_FOUND)
    message(FATAL_ERROR "Unable to find python matching: ${EXECUTABLE}.")
  endif()
else()
  find_package(Python3 REQUIRED COMPONENTS Development Development.SABIModule Interpreter)
endif()

append_cmake_prefix_path("torch" "torch.utils.cmake_prefix_path")

find_package(Torch REQUIRED)

if (NOT TARGET_DEVICE STREQUAL "cuda" AND
    NOT TARGET_DEVICE STREQUAL "rocm")
    return()
endif()

if(DEFINED CMAKE_CUDA_COMPILER_VERSION AND
   CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL 13.0)
 set(CUDA_DEFAULT_KERNEL_ARCHS "7.5;8.0;8.6;8.7;8.9;9.0;10.0;11.0;12.0+PTX")
elseif(DEFINED CMAKE_CUDA_COMPILER_VERSION AND
   CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL 12.8)
 set(CUDA_DEFAULT_KERNEL_ARCHS "7.0;7.2;7.5;8.0;8.6;8.7;8.9;9.0;10.0;10.1;12.0+PTX")
else()
  set(CUDA_DEFAULT_KERNEL_ARCHS "7.0;7.2;7.5;8.0;8.6;8.7;8.9;9.0+PTX")
endif()

if (NOT HIP_FOUND AND CUDA_FOUND)
  set(GPU_LANG "CUDA")

  {% if cuda_minver %}
    if (CUDA_VERSION VERSION_LESS {{ cuda_minver }})
      message(FATAL_ERROR "CUDA version ${CUDA_VERSION} is too old. "
        "Minimum required version is {{ cuda_minver }}.")
    endif()
  {% endif %}

  {% if cuda_maxver %}
    if (CUDA_VERSION VERSION_GREATER {{ cuda_maxver }})
      message(FATAL_ERROR "CUDA version ${CUDA_VERSION} is too new. "
        "Maximum version is {{ cuda_maxver }}.")
    endif()
  {% endif %}

elseif(HIP_FOUND)
  set(GPU_LANG "HIP")

  # Importing torch recognizes and sets up some HIP/ROCm configuration but does
  # not let cmake recognize .hip files. In order to get cmake to understand the
  # .hip extension automatically, HIP must be enabled explicitly.
  enable_language(HIP)
else()
  message(FATAL_ERROR "Can't find CUDA or HIP installation.")
endif()


if(GPU_LANG STREQUAL "CUDA")
  clear_cuda_arches(CUDA_ARCH_FLAGS)
  extract_unique_cuda_archs_ascending(CUDA_ARCHS "${CUDA_ARCH_FLAGS}")
  message(STATUS "CUDA target architectures: ${CUDA_ARCHS}")
  # Filter the target architectures by the supported supported archs
  # since for some files we will build for all CUDA_ARCHS.
  cuda_archs_loose_intersection(CUDA_ARCHS "${CUDA_SUPPORTED_ARCHS}" "${CUDA_ARCHS}")
  message(STATUS "CUDA supported target architectures: ${CUDA_ARCHS}")

  if(NVCC_THREADS AND GPU_LANG STREQUAL "CUDA")
    list(APPEND GPU_FLAGS "--threads=${NVCC_THREADS}")
  endif()

  add_compile_definitions(CUDA_KERNEL)
elseif(GPU_LANG STREQUAL "HIP")
  override_gpu_arches(GPU_ARCHES HIP ${HIP_SUPPORTED_ARCHS})
  set(ROCM_ARCHS ${GPU_ARCHES})
  message(STATUS "ROCM supported target architectures: ${ROCM_ARCHS}")

  add_compile_definitions(ROCM_KERNEL)
else()
  override_gpu_arches(GPU_ARCHES
    ${GPU_LANG}
    "${${GPU_LANG}_SUPPORTED_ARCHS}")
endif()


message(STATUS "Rendered for platform {{ platform }}")
{% if platform == 'windows' %}
include(${CMAKE_CURRENT_LIST_DIR}/cmake/windows.cmake)

# This preprocessor macro should be defined in building with MSVC but not for CUDA and co.
# Also, if not using MVSC, this may not be set too ...
# So we explicitly set it to avoid any side effect due to preprocessor-guards not being defined.
add_compile_definitions(_WIN32>)

# Generate standardized build name
run_python(TORCH_VERSION "import torch; print(torch.__version__.split('+')[0])" "Failed to get Torch version")
run_python(CXX11_ABI_VALUE "import torch; print('TRUE' if torch._C._GLIBCXX_USE_CXX11_ABI else 'FALSE')" "Failed to get CXX11 ABI")
cmake_host_system_information(RESULT HOST_ARCH QUERY OS_PLATFORM)

set(SYSTEM_STRING "${HOST_ARCH}-windows")

if(GPU_LANG STREQUAL "CUDA")
  generate_build_name(BUILD_VARIANT_NAME "${TORCH_VERSION}" ${CXX11_ABI_VALUE} "cuda" "${CUDA_VERSION}" "${SYSTEM_STRING}")
elseif(GPU_LANG STREQUAL "HIP")
  run_python(ROCM_VERSION "import torch.version; print(torch.version.hip.split('.')[0] + '.' + torch.version.hip.split('.')[1])" "Failed to get ROCm version")
  generate_build_name(BUILD_VARIANT_NAME "${TORCH_VERSION}" ${CXX11_ABI_VALUE} "rocm" "${ROCM_VERSION}" "${SYSTEM_STRING}")
endif()
{% endif %}
