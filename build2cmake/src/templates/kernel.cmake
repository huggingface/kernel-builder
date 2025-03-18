set({{kernel_name}}_SRC
  {{ sources }}
)

{% if includes %}
# TODO: check if CLion support this:
# https://youtrack.jetbrains.com/issue/CPP-16510/CLion-does-not-handle-per-file-include-directories
set_source_files_properties(
  {{'${' + kernel_name + '_SRC}'}}
  PROPERTIES INCLUDE_DIRECTORIES "{{ includes }}")
{% endif %}

if(GPU_LANG STREQUAL "CUDA")
  cuda_archs_loose_intersection({{kernel_name}}_ARCHS "{{ cuda_capabilities|join(";") }}" ${CUDA_ARCHS})
  set_gencode_flags_for_srcs(SRCS {{'"${' + kernel_name + '_SRC}"'}} CUDA_ARCHS {{ '${' + kernel_name + '_ARCHS}'}})
  list(APPEND SRC {{'"${' + kernel_name + '_SRC}"'}})
{% if language == "cuda-hipify" %}
elseif(GPU_LANG STREQUAL "HIP")
  # We currently don't use the archs yet.
  # set({{kernel_name}}_ARCHS "{{ rocm_archs|join(";") }}")
  list(APPEND SRC {{'"${' + kernel_name + '_SRC}"'}})
{% endif %}
endif()

