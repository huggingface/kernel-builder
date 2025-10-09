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
endif()

# Add kernels_install target for huggingface/kernels library layout
add_kernels_install_target({{ ops_name }} "{{ name }}" "${BUILD_VARIANT_NAME}")

# Add local_install target for local development with get_local_kernel()
add_local_install_target({{ ops_name }} "{{ name }}" "${BUILD_VARIANT_NAME}")