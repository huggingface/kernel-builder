cmake_minimum_required(VERSION 3.26)
project({{name}} LANGUAGES CXX CUDA)

install(CODE "set(CMAKE_INSTALL_LOCAL_ONLY TRUE)" ALL_COMPONENTS)

include(FetchContent)
file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}) # Ensure the directory exists
message(STATUS "FetchContent base directory: ${FETCHCONTENT_BASE_DIR}")

set(CUDA_SUPPORTED_ARCHS "7.0;7.2;7.5;8.0;8.6;8.7;8.9;9.0")

# Hardcoded for now, update.
set(GPU_LANGUAGE "CUDA")

include(${CMAKE_CURRENT_LIST_DIR}/cmake/utils.cmake)

append_cmake_prefix_path("torch" "torch.utils.cmake_prefix_path")

find_package(Torch REQUIRED)

clear_cuda_arches(CUDA_ARCH_FLAGS)
extract_unique_cuda_archs_ascending(CUDA_ARCHS "${CUDA_ARCH_FLAGS}")
message(STATUS "CUDA target architectures: ${CUDA_ARCHS}")

# Filter the target architectures by the supported supported archs
# since for some files we will build for all CUDA_ARCHS.
cuda_archs_loose_intersection(CUDA_ARCHS "${CUDA_SUPPORTED_ARCHS}" "${CUDA_ARCHS}")
message(STATUS "CUDA supported target architectures: ${CUDA_ARCHS}")
