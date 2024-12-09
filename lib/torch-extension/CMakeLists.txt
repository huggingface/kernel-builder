cmake_minimum_required(VERSION 3.13)
project(kernel LANGUAGES CXX CUDA)

find_package(Python REQUIRED COMPONENTS Development Development.SABIModule)

# Remove once we have the shim.
find_package(Torch REQUIRED)

if(NOT DEFINED EXTENSION_NAME)
  message(FATAL_ERROR "EXTENSION_NAME must be defined")
endif()

if(NOT DEFINED EXTENSION_DEST)
  message(FATAL_ERROR "EXTENSION_DEST must be defined")
endif()

if(DEFINED EXTENSION_SOURCES)
  set(SOURCE_FILES ${EXTENSION_SOURCES})
else()
  message(FATAL_ERROR "EXTENSION_SOURCES must be defined")
endif()

if(DEFINED EXTENSION_INCLUDE_DIRS)
  include_directories(${EXTENSION_INCLUDE_DIRS})
endif()

if(NOT DEFINED KERNEL_LIBRARIES)
  message(FATAL_ERROR "KERNEL_LIBRARIES must be defined")
endif()

Python_add_library(${EXTENSION_NAME} USE_SABI 3 WITH_SOABI MODULE "${SOURCE_FILES}")
target_compile_definitions(${EXTENSION_NAME} PRIVATE "-DTORCH_EXTENSION_NAME=${EXTENSION_NAME}")
target_link_libraries(${EXTENSION_NAME} PRIVATE CUDA::cudart CUDA::cuda_driver)

target_link_libraries(${EXTENSION_NAME} PRIVATE torch torch_python)
target_link_libraries(${EXTENSION_NAME} PRIVATE ${KERNEL_LIBRARIES})
set_target_properties(${EXTENSION_NAME} PROPERTIES
  CUDA_RESOLVE_DEVICE_SYMBOLS ON)

install(TARGETS ${EXTENSION_NAME} LIBRARY COMPONENT ${EXTENSION_NAME} DESTINATION ${EXTENSION_DEST})

