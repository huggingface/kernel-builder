cmake_minimum_required(VERSION 3.13)
project(kernel LANGUAGES CXX CUDA)

# Remove once we have the shim.
find_package(Torch REQUIRED)

if(NOT DEFINED KERNEL_NAME)
  message(FATAL_ERROR "KERNEL_NAME must be defined")
endif()


if(DEFINED KERNEL_SOURCES)
  set(SOURCE_FILES ${KERNEL_SOURCES})
else()
  message(FATAL_ERROR "KERNEL_SOURCES must be defined")
endif()

if(DEFINED KERNEL_INCLUDE_DIRS)
  include_directories(${KERNEL_INCLUDE_DIRS})
endif()

set(GPU_COMPILE_FLAGS "")

add_library(${KERNEL_NAME} STATIC ${SOURCE_FILES})

target_compile_options(${KERNEL_NAME} PRIVATE
  $<$<COMPILE_LANGUAGE:CUDA>:${GPU_COMPILE_FLAGS}>)

target_link_libraries(${KERNEL_NAME} PRIVATE ${TORCH_LIBRARIES})
set_target_properties(${EXTENSION_NAME} PROPERTIES
  CUDA_RESOLVE_DEVICE_SYMBOLS ON)

install(TARGETS ${KERNEL_NAME} ARCHIVE COMPONENT Development DESTINATION lib)

