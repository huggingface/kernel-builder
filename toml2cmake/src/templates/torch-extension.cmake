find_package(Torch REQUIRED)
find_package(Python REQUIRED COMPONENTS Development Development.SABIModule)

get_torch_gpu_compiler_flags(GPU_FLAGS ${GPU_LANGUAGE})

set(TORCH_{{name}}_SRC
  {{ src|join(' ') }}
)

{% if includes %}
# TODO: check if CLion support this:
# https://youtrack.jetbrains.com/issue/CPP-16510/CLion-does-not-handle-per-file-include-directories
set_source_files_properties(
  {{'${TORCH_' + name + '_SRC}'}}
  PROPERTIES INCLUDE_DIRECTORIES "{{ includes }}")
{% endif %}

list(APPEND SRC {{'"${TORCH_' + name + '_SRC}"'}})

define_gpu_extension_target(
  {{ ext_name }}
  DESTINATION {{ ext_name }}
  LANGUAGE ${GPU_LANGUAGE}
  SOURCES ${SRC}
  COMPILE_FLAGS ${GPU_FLAGS}
  ARCHITECTURES ${GPU_ARCHITECTURES}
  #INCLUDE_DIRECTORIES ${CUTLASS_INCLUDE_DIR}
  USE_SABI 3
  WITH_SOABI)

target_link_options({{ ext_name }} PRIVATE -static-libstdc++)

