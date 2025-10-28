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

add_compile_definitions(CPU_KERNEL)
