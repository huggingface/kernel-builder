cmake_minimum_required(VERSION 3.26)
project({{name}} LANGUAGES CXX)

set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum macOS deployment version")

install(CODE "set(CMAKE_INSTALL_LOCAL_ONLY TRUE)" ALL_COMPONENTS)

include(FetchContent)
file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}) # Ensure the directory exists
message(STATUS "FetchContent base directory: ${FETCHCONTENT_BASE_DIR}")

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

add_compile_definitions(METAL_KERNEL)

# Initialize list for Metal shader sources
set(ALL_METAL_SOURCES)

# Generate standardized build name
run_python(TORCH_VERSION "import torch; print(torch.__version__.split('+')[0])" "Failed to get Torch version")
run_python(CXX11_ABI_VALUE "import torch; print('TRUE' if torch._C._GLIBCXX_USE_CXX11_ABI else 'FALSE')" "Failed to get CXX11 ABI")
cmake_host_system_information(RESULT HOST_ARCH QUERY OS_PLATFORM)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(SYSTEM_STRING "${HOST_ARCH}-darwin")
else()
  message(FATAL_ERROR "Metal is only supported on macOS/Darwin")
endif()

# Metal doesn't have a version - it's tied to the OS
generate_build_name(BUILD_VARIANT_NAME "${TORCH_VERSION}" ${CXX11_ABI_VALUE} "metal" "0" "${SYSTEM_STRING}")
