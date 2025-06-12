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
  
  # Get the metallib file path
  get_target_property(METALLIB_FILE {{ ops_name }} METALLIB_FILE)
  
  # Copy metallib to the output directory (same as the .so file)
  add_custom_command(TARGET {{ ops_name }} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    ${METALLIB_FILE}
    $<TARGET_FILE_DIR:{{ ops_name }}>/{{ ops_name }}.metallib
    COMMENT "Copying metallib to output directory"
  )
  
  # Also copy to the source directory for editable installs
  add_custom_command(TARGET {{ ops_name }} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    ${METALLIB_FILE}
    ${CMAKE_CURRENT_SOURCE_DIR}/torch-ext/{{ name }}/{{ ops_name }}.metallib
    COMMENT "Copying metallib to source directory for editable installs"
  )
  
  # Use a relative path for runtime loading
  target_compile_definitions({{ ops_name }} PRIVATE METALLIB_PATH="{{ ops_name }}.metallib")
endif()