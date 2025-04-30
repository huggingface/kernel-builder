cmake_minimum_required(VERSION 3.26)
project({{name}} LANGUAGES CXX)


# Low-memory friendly defaults

# Switch on automatically when the caller did **not** ask for a build type
# (i.e. developer didn’t override with -DCMAKE_BUILD_TYPE=Debug or such)
if(NOT CMAKE_BUILD_TYPE)
  set(LOW_MEM ON)
endif()

# or if the env-var is set
if(DEFINED ENV{LOW_MEM_BUILD} AND ENV{LOW_MEM_BUILD})
  set(LOW_MEM ON)
endif()

if(LOW_MEM)
  message(STATUS "LOW_MEM: low memory build enabled")

  # Use a single thread for nvcc compilation
  if(NOT DEFINED NVCC_THREADS)
    # allow env override otherwise fall back to 1
    if(DEFINED ENV{nvccThreads})
      set(NVCC_THREADS $ENV{nvccThreads})
    else()
      set(NVCC_THREADS 1)
    endif()
  endif()

  # CMake/Ninja to issue only one job at a time
  # https://cmake.org/pipermail/cmake/2019-February/069021.html
  if(CMAKE_GENERATOR STREQUAL "Ninja")
    # Define a job pool with a single job
    set_property(GLOBAL PROPERTY JOB_POOLS single=1)
    set(CMAKE_JOB_POOL_COMPILE single)
    set(CMAKE_JOB_POOL_LINK    single)
  endif()


  # ld normally optimizes for speed over memory usage by caching the 
  # symbol tables of input files in memory. This option tells ld to 
  # instead optimize for memory usage, by rereading the symbol tables 
  # as necessary
  # https://sourceware.org/binutils/docs-2.26/ld/Options.html
  add_link_options(-Wl,--no-keep-memory)

  # Use the lighter LLVM linker if it is available
  # https://lists.llvm.org/pipermail/llvm-dev/2018-September/126305.html
  find_program(LLD_PATH NAMES ld.lld lld)
  if(LLD_PATH)
    message(STATUS "LOW_MEM: using ld.lld for host link")
    set(CMAKE_LINKER            ${LLD_PATH})
    set(CMAKE_CUDA_HOST_LINK_LAUNCHER "${LLD_PATH}")
    foreach(mode EXECUTABLE SHARED MODULE STATIC)
      set(CMAKE_${mode}_LINKER_FLAGS
          "${CMAKE_${mode}_LINKER_FLAGS} -fuse-ld=lld")
    endforeach()
  endif()

  # default to a *Release*-like profile to avoid giant object files
  # allow override with -DCMAKE_BUILD_TYPE=Release
  if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Omit debug info to save RAM")
  endif()
endif()


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

if (NOT HIP_FOUND AND CUDA_FOUND)
  set(GPU_LANG "CUDA")
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
elseif(GPU_LANG STREQUAL "HIP")
  set(ROCM_ARCHS "${HIP_SUPPORTED_ARCHS}")
  # TODO: remove this once we can set specific archs per source file set.
  override_gpu_arches(GPU_ARCHES
    ${GPU_LANG}
    "${${GPU_LANG}_SUPPORTED_ARCHS}")
else()
  override_gpu_arches(GPU_ARCHES
    ${GPU_LANG}
    "${${GPU_LANG}_SUPPORTED_ARCHS}")
endif()
