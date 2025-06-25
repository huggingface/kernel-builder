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
  {% if cuda_capabilities %}
    cuda_archs_loose_intersection({{kernel_name}}_ARCHS "{{ cuda_capabilities|join(";") }}" "${CUDA_ARCHS}")
  {% else %}
    cuda_archs_loose_intersection({{kernel_name}}_ARCHS "${CUDA_SUPPORTED_ARCHS}" "${CUDA_ARCHS}")
  {% endif %}
  message(STATUS "Capabilities for kernel {{kernel_name}}: {{ '${' + kernel_name + '_ARCHS}'}}")
  set_gencode_flags_for_srcs(SRCS {{'"${' + kernel_name + '_SRC}"'}} CUDA_ARCHS "{{ '${' + kernel_name + '_ARCHS}'}}")

  {% if cuda_flags %}

  foreach(_KERNEL_SRC {{'${' + kernel_name + '_SRC}'}})
    if(_KERNEL_SRC MATCHES ".*\\.cu$")
      set_property(
        SOURCE ${_KERNEL_SRC}
        APPEND PROPERTY
        COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:CUDA>:{{ cuda_flags }}>"
      )
    endif()
  endforeach()
  {% endif %}

  {% if cxx_flags %}
  foreach(_KERNEL_SRC {{'${' + kernel_name + '_SRC}'}})
    set_property(
      SOURCE ${_KERNEL_SRC}
      APPEND PROPERTY
      COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:CXX>:{{ cxx_flags }}>"
    )
  endforeach()
  {% endif %}

  list(APPEND SRC {{'"${' + kernel_name + '_SRC}"'}})
{% if supports_hipify %}
elseif(GPU_LANG STREQUAL "HIP")
  hip_archs_loose_intersection({{kernel_name}}_ARCHS "{{ rocm_archs|join(";") }}" ${ROCM_ARCHS})
  list(APPEND SRC {{'"${' + kernel_name + '_SRC}"'}})
{% endif %}
endif()

