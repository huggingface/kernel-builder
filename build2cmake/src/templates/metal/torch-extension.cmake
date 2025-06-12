# Include Metal shader compilation utilities
include(${CMAKE_CURRENT_LIST_DIR}/cmake/compile-metal.cmake)

define_gpu_extension_target(
  {{ ops_name }}
  DESTINATION {{ ops_name }}
  LANGUAGE ${GPU_LANG}
  SOURCES ${SRC}
  COMPILE_FLAGS ${GPU_FLAGS}
  ARCHITECTURES ${GPU_ARCHES}
  USE_SABI 3
  WITH_SOABI)

# Compile Metal shaders if any were found
if(ALL_METAL_SOURCES)
  compile_metal_shaders({{ ops_name }} "${ALL_METAL_SOURCES}")
  
  # Add metallib path as a compile definition so runtime can find it
  get_target_property(METALLIB_FILE {{ ops_name }} METALLIB_FILE)
  target_compile_definitions({{ ops_name }} PRIVATE METALLIB_PATH="${METALLIB_FILE}")
endif()