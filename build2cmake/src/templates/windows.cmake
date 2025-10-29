# Generate a standardized build variant name following the pattern:
# torch<VERSION>-<ABI>-<COMPUTE>-windows
#
# Arguments:
#   OUT_BUILD_NAME - Output variable name
#   TORCH_VERSION - PyTorch version (e.g., "2.7.1")
#   CXX11_ABI - Whether C++11 ABI is enabled (TRUE/FALSE)
#   COMPUTE_FRAMEWORK - One of: cuda, rocm, metal, xpu
#   COMPUTE_VERSION - Version of compute framework (e.g., "12.4" for CUDA, "6.0" for ROCm)
# Example output: torch271-cxx11-cu124-x86_64-windows
#
function(generate_build_name OUT_BUILD_NAME TORCH_VERSION CXX11_ABI COMPUTE_FRAMEWORK COMPUTE_VERSION)
    # Flatten version by removing dots and padding to 2 components
    string(REPLACE "." ";" VERSION_LIST "${TORCH_VERSION}")
    list(LENGTH VERSION_LIST VERSION_COMPONENTS)

    # Pad to at least 2 components
    if(VERSION_COMPONENTS LESS 2)
        list(APPEND VERSION_LIST "0")
    endif()

    # Take first 2 components and join without dots
    list(GET VERSION_LIST 0 MAJOR)
    list(GET VERSION_LIST 1 MINOR)
    set(FLATTENED_TORCH "${MAJOR}${MINOR}")

    # Generate compute string
    if(COMPUTE_FRAMEWORK STREQUAL "cuda")
        # Flatten CUDA version (e.g., "12.4" -> "124")
        string(REPLACE "." ";" COMPUTE_VERSION_LIST "${COMPUTE_VERSION}")
        list(LENGTH COMPUTE_VERSION_LIST COMPUTE_COMPONENTS)
        if(COMPUTE_COMPONENTS GREATER_EQUAL 2)
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            list(GET COMPUTE_VERSION_LIST 1 COMPUTE_MINOR)
            set(COMPUTE_STRING "cu${COMPUTE_MAJOR}${COMPUTE_MINOR}")
        else()
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            set(COMPUTE_STRING "cu${COMPUTE_MAJOR}0")
        endif()
    elseif(COMPUTE_FRAMEWORK STREQUAL "rocm")
        # Flatten ROCm version (e.g., "6.0" -> "60")
        string(REPLACE "." ";" COMPUTE_VERSION_LIST "${COMPUTE_VERSION}")
        list(LENGTH COMPUTE_VERSION_LIST COMPUTE_COMPONENTS)
        if(COMPUTE_COMPONENTS GREATER_EQUAL 2)
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            list(GET COMPUTE_VERSION_LIST 1 COMPUTE_MINOR)
            set(COMPUTE_STRING "rocm${COMPUTE_MAJOR}${COMPUTE_MINOR}")
        else()
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            set(COMPUTE_STRING "rocm${COMPUTE_MAJOR}0")
        endif()
    elseif(COMPUTE_FRAMEWORK STREQUAL "xpu")
        # Flatten XPU version (e.g., "2025.2" -> "202552")
        string(REPLACE "." ";" COMPUTE_VERSION_LIST "${COMPUTE_VERSION}")
        list(LENGTH COMPUTE_VERSION_LIST COMPUTE_COMPONENTS)
        if(COMPUTE_COMPONENTS GREATER_EQUAL 2)
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            list(GET COMPUTE_VERSION_LIST 1 COMPUTE_MINOR)
            set(COMPUTE_STRING "xpu${COMPUTE_MAJOR}${COMPUTE_MINOR}")
        else()
            list(GET COMPUTE_VERSION_LIST 0 COMPUTE_MAJOR)
            set(COMPUTE_STRING "xpu${COMPUTE_MAJOR}0")
        endif()
    else()
        message(FATAL_ERROR "Unknown compute framework: ${COMPUTE_FRAMEWORK}")
    endif()

    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
        set(CPU_ARCH "x86_64")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set(CPU_ARCH "aarch64")
    else()
        message(ERROR "Unsupported Windows platform ${CMAKE_SYSTEM_PROCESSOR}")
    endif()

    # Assemble the final build name
    if(CXX11_ABI STREQUAL "" OR CXX11_ABI STREQUAL "FALSE")
        set(BUILD_NAME "torch${FLATTENED_TORCH}-${COMPUTE_STRING}-${CPU_ARCH}-windows")
    else()
        set(BUILD_NAME "torch${FLATTENED_TORCH}-cxx11-${COMPUTE_STRING}-${CPU_ARCH}-windows")
    endif()

    set(${OUT_BUILD_NAME} "${BUILD_NAME}" PARENT_SCOPE)
    message(STATUS "Generated build name: ${BUILD_NAME}")
endfunction()

#
# Create a custom install target for the huggingface/kernels library layout.
# This installs the extension into a directory structure suitable for kernel hub discovery:
#   <PREFIX>/<BUILD_VARIANT_NAME>/<PACKAGE_NAME>/
#
# Arguments:
#   TARGET_NAME - Name of the target to create the install rule for
#   PACKAGE_NAME - Python package name (e.g., "activation")
#   BUILD_VARIANT_NAME - Build variant name (e.g., "torch271-cxx11-cu124-x86_64-linux")
#   INSTALL_PREFIX - Base installation directory (defaults to CMAKE_INSTALL_PREFIX)
#
function(add_kernels_install_target TARGET_NAME PACKAGE_NAME BUILD_VARIANT_NAME)
    set(oneValueArgs INSTALL_PREFIX)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "" ${ARGN})

    if(NOT ARG_INSTALL_PREFIX)
        set(ARG_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")
    endif()

    # Set the installation directory
    set(KERNEL_INSTALL_DIR "${ARG_INSTALL_PREFIX}/${BUILD_VARIANT_NAME}/${PACKAGE_NAME}")

    message(STATUS "Using PACKAGE_NAME: ${PACKAGE_NAME}")

    # Install the compiled extension using CMake's install() command
    # This will be triggered by the standard INSTALL target
    install(TARGETS ${TARGET_NAME}
        LIBRARY DESTINATION "${KERNEL_INSTALL_DIR}"
        RUNTIME DESTINATION "${KERNEL_INSTALL_DIR}"
        COMPONENT ${TARGET_NAME})

    # Glob Python files to install
    file(GLOB PYTHON_FILES "${CMAKE_SOURCE_DIR}/torch-ext/${PACKAGE_NAME}/*.py")

    # Install Python files (__init__.py and _ops.py)
    install(FILES ${PYTHON_FILES}
        DESTINATION "${KERNEL_INSTALL_DIR}"
        COMPONENT ${TARGET_NAME})

    # Install README.md if it exists at the root
    if(EXISTS "${CMAKE_SOURCE_DIR}/README.md")
        install(FILES "${CMAKE_SOURCE_DIR}/README.md"
            DESTINATION "${ARG_INSTALL_PREFIX}/${BUILD_VARIANT_NAME}"
            COMPONENT ${TARGET_NAME})
    endif()

    message(STATUS "Added install rules for ${TARGET_NAME} -> ${BUILD_VARIANT_NAME}/${PACKAGE_NAME}")
endfunction()

#
# Add install rules for local development with huggingface/kernels.
# This installs the extension into the layout expected by get_local_kernel():
#   ${CMAKE_SOURCE_DIR}/build/<BUILD_VARIANT_NAME>/<PACKAGE_NAME>/
#
# This allows developers to use get_local_kernel() from the kernels library to load
# locally built kernels without needing to publish to the hub.
#
# This uses the standard CMake install() command, so it works with the default
# "install" target that is always available.
#
# Arguments:
#   TARGET_NAME - Name of the target to create the install rule for
#   PACKAGE_NAME - Python package name (e.g., "activation")
#   BUILD_VARIANT_NAME - Build variant name (e.g., "torch271-cxx11-cu124-x86_64-linux")
#
function(add_local_install_target TARGET_NAME PACKAGE_NAME BUILD_VARIANT_NAME)
    # Define your local, folder based, installation directory
    set(LOCAL_INSTALL_DIR "${CMAKE_SOURCE_DIR}/build/${BUILD_VARIANT_NAME}/${PACKAGE_NAME}")

    # Glob Python files at configure time
    file(GLOB PYTHON_FILES "${CMAKE_SOURCE_DIR}/torch-ext/${PACKAGE_NAME}/*.py")

    # Create a custom target for local installation
    add_custom_target(local_install
            COMMENT "Installing files to local directory..."
    )

    # Add custom commands to copy files
    add_custom_command(TARGET local_install POST_BUILD
            # Copy the shared library
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:${TARGET_NAME}>
            ${LOCAL_INSTALL_DIR}/

            # Copy each Python file
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${PYTHON_FILES}
            ${LOCAL_INSTALL_DIR}/

            COMMENT "Copying shared library and Python files to ${LOCAL_INSTALL_DIR}"
            COMMAND_EXPAND_LISTS
    )

    # Copy README.md if it exists at the root
    if(EXISTS "${CMAKE_SOURCE_DIR}/README.md")
        add_custom_command(TARGET local_install POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${CMAKE_SOURCE_DIR}/README.md"
                "${CMAKE_SOURCE_DIR}/build/${BUILD_VARIANT_NAME}/"
                COMMENT "Copying README.md to ${CMAKE_SOURCE_DIR}/build/${BUILD_VARIANT_NAME}/"
        )
    endif()

    file(MAKE_DIRECTORY ${LOCAL_INSTALL_DIR})
    message(STATUS "Added install rules for ${TARGET_NAME} -> build/${BUILD_VARIANT_NAME}/${PACKAGE_NAME}")
endfunction()
