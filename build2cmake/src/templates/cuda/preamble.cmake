cmake_minimum_required(VERSION 3.26)
project({{name}} LANGUAGES CXX)

set(TARGET_DEVICE "cuda" CACHE STRING "Target device backend for kernel")

install(CODE "set(CMAKE_INSTALL_LOCAL_ONLY TRUE)" ALL_COMPONENTS)

include(FetchContent)
file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}) # Ensure the directory exists
message(STATUS "FetchContent base directory: ${FETCHCONTENT_BASE_DIR}")

set(CUDA_SUPPORTED_ARCHS "{{ cuda_supported_archs }}")

set(HIP_SUPPORTED_ARCHS "gfx906;gfx908;gfx90a;gfx940;gfx941;gfx942;gfx1030;gfx1100;gfx1101")

include(${CMAKE_CURRENT_LIST_DIR}/cmake/utils.cmake)

if(DEFINED Python_EXECUTABLE)
  # Allow passing through the interpreter (e.g. from setup.py).
  find_package(Python COMPONENTS Development Development.SABIModule Interpreter)
  if (NOT Python_FOUND)
    message(FATAL_ERROR "Unable to find python matching: ${EXECUTABLE}.")
  endif()
else()
  find_package(Python REQUIRED COMPONENTS Development Development.SABIModule Interpreter)
endif()

append_cmake_prefix_path("torch" "torch.utils.cmake_prefix_path")

find_package(Torch REQUIRED)

if (NOT TARGET_DEVICE STREQUAL "cuda" AND
    NOT TARGET_DEVICE STREQUAL "rocm")
    return()
endif()

if(DEFINED CMAKE_CUDA_COMPILER_VERSION AND
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
  set(ROCM_ARCHS "${HIP_SUPPORTED_ARCHS}")
  # TODO: remove this once we can set specific archs per source file set.
  override_gpu_arches(GPU_ARCHES
    ${GPU_LANG}
    "${${GPU_LANG}_SUPPORTED_ARCHS}")

  add_compile_definitions(ROCM_KERNEL)
else()
  override_gpu_arches(GPU_ARCHES
    ${GPU_LANG}
    "${${GPU_LANG}_SUPPORTED_ARCHS}")
endif()
