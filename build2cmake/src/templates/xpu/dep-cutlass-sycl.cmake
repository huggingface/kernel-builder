find_package(CutlassSycl)

if (NOT CutlassSycl_FOUND)
  set(CUTLASS_ENABLE_HEADERS_ONLY ON CACHE BOOL "Enable only the header library")
  set(CUTLASS_ENABLE_BENCHMARKS OFF CACHE BOOL "Disable CUTLASS Benchmarks")

# Set CUTLASS_REVISION manually -- its revision detection doesn't work in this case.
  set(CUTLASS_REVISION "v{{ version }}" CACHE STRING "CUTLASS revision to use")

# Use the specified CUTLASS source directory for compilation if CUTLASS_SYCL_SRC_DIR is provided
  if (DEFINED ENV{CUTLASS_SYCL_SRC_DIR})
    set(CUTLASS_SYCL_SRC_DIR $ENV{CUTLASS_SYCL_SRC_DIR})
  endif()

  if(CUTLASS_SYCL_SRC_DIR)
    if(NOT IS_ABSOLUTE CUTLASS_SYCL_SRC_DIR)
      get_filename_component(CUTLASS_SYCL_SRC_DIR "${CUTLASS_SYCL_SRC_DIR}" ABSOLUTE)
    endif()
    message(STATUS "The CUTLASS_SYCL_SRC_DIR is set, using ${CUTLASS_SYCL_SRC_DIR} for compilation")
    FetchContent_Declare(cutlass SOURCE_DIR ${CUTLASS_SYCL_SRC_DIR})
  else()
    FetchContent_Declare(
        cutlass
        GIT_REPOSITORY https://github.com/intel/cutlass-sycl.git
        GIT_TAG ${CUTLASS_REVISION}
        GIT_PROGRESS TRUE

        # Speed up CUTLASS download by retrieving only the specified GIT_TAG instead of the history.
        # Important: If GIT_SHALLOW is enabled then GIT_TAG works only with branch names and tags.
        # So if the GIT_TAG above is updated to a commit hash, GIT_SHALLOW must be set to FALSE
        GIT_SHALLOW TRUE
    )
  endif()

  # Set Intel backend env
  message(STATUS "Setting Intel GPU optimization env vars for Cutlass-SYCL")
  string(REPLACE "-fsycl-targets=spir64_gen,spir64" "-fsycl-targets=intel_gpu_pvc" sycl_link_flags "${sycl_link_flags}")
  string(REPLACE "-device pvc,xe-lpg,ats-m150" "" sycl_link_flags "${sycl_link_flags}")
  string(APPEND sycl_link_flags "-Xspirv-translator;-spirv-ext=+SPV_INTEL_split_barrier;")
  string(REPLACE "-fsycl-targets=spir64_gen,spir64" "-fsycl-targets=intel_gpu_pvc" sycl_flags "${sycl_flags}")

  set(CUTLASS_ENABLE_SYCL ON CACHE BOOL "Enable SYCL for CUTLASS")
  add_compile_definitions(CUTLASS_ENABLE_SYCL=1)
  set(DPCPP_SYCL_TARGET "intel_gpu_pvc" CACHE STRING "SYCL target for Intel GPU")
  add_compile_definitions(DPCPP_SYCL_TARGET=intel_gpu_pvc)
  set(SYCL_INTEL_TARGET ON CACHE BOOL "Enable SYCL for INTEL")
  add_compile_definitions(SYCL_INTEL_TARGET=1)
  
  set(ENV{SYCL_PROGRAM_COMPILE_OPTIONS} "-ze-opt-large-register-file")
  set(ENV{IGC_VISAOptions} "-perfmodel")
  set(ENV{IGC_VectorAliasBBThreshold} "10000")
  set(ENV{IGC_ExtraOCLOptions} "-cl-intel-256-GRF-per-thread")

  FetchContent_MakeAvailable(cutlass)

  include_directories(${CUTLASS_INCLUDE_DIR})
  include_directories(${CUTLASS_TOOLS_UTIL_INCLUDE_DIR})
else()
  message(STATUS "Using system cutlass with version: ${CutlassSycl_VERSION}")
endif(NOT CutlassSycl_FOUND)
