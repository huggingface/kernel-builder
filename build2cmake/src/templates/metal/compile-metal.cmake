# Metal shader compilation function
function(compile_metal_shaders TARGET_NAME METAL_SOURCES)
    # Find the Metal launcher (we'll force DEVELOPER_DIR per call)
    find_program(METAL_COMPILER xcrun REQUIRED)
    find_program(XCODE_SELECT xcode-select REQUIRED)
    # --- Auto-detect DEVELOPER_DIR ---
    set(METAL_DEVELOPER_DIR "")

    # 1) Prefer xcode-select
    execute_process(
        COMMAND ${XCODE_SELECT} -p
        OUTPUT_VARIABLE _XCODE_DEV
        RESULT_VARIABLE _XCODE_RC
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_XCODE_RC EQUAL 0 AND EXISTS "${_XCODE_DEV}")
        set(METAL_DEVELOPER_DIR "${_XCODE_DEV}")
    endif()

    # 2) If it points to CommandLineTools or is empty, try Xcode apps (pick newest)
    if(NOT METAL_DEVELOPER_DIR OR METAL_DEVELOPER_DIR MATCHES "CommandLineTools")
        file(GLOB _XCODE_CANDIDATES "/Applications/Xcode*.app/Contents/Developer")
        list(SORT _XCODE_CANDIDATES DESCENDING)
        foreach(_cand ${_XCODE_CANDIDATES})
            if(EXISTS "${_cand}/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal")
                set(METAL_DEVELOPER_DIR "${_cand}")
                break()
            endif()
        endforeach()
    endif()

    # 3) Fallback to the standard Xcode path
    if(NOT METAL_DEVELOPER_DIR)
        set(METAL_DEVELOPER_DIR "/Applications/Xcode.app/Contents/Developer")
    endif()

    message(STATUS "Detected DEVELOPER_DIR for Metal: ${METAL_DEVELOPER_DIR}")

    # Metal flags
    set(METAL_FLAGS "-std=metal3.2" "-O2")

    # Output directory for compiled metallib
    set(METALLIB_OUTPUT_DIR "${CMAKE_BINARY_DIR}/metallib")
    file(MAKE_DIRECTORY ${METALLIB_OUTPUT_DIR})

    # Include dirs for shaders
    set(METAL_INCLUDE_DIRS
        "${CMAKE_SOURCE_DIR}/gptoss_kernels/source/include"
        "${CMAKE_SOURCE_DIR}/gptoss_kernels/include"
        "${CMAKE_SOURCE_DIR}/."
    )
    foreach(INC ${METAL_INCLUDE_DIRS})
        list(APPEND METAL_FLAGS "-I${INC}")
    endforeach()

    # Separate .metal files
    set(AIR_FILES)
    set(METAL_FILES)
    set(HEADER_FILES)
    foreach(SOURCE_FILE ${METAL_SOURCES})
        if(SOURCE_FILE MATCHES "\\.metal$")
            list(APPEND METAL_FILES ${SOURCE_FILE})
        elseif(SOURCE_FILE MATCHES "\\.h$")
            list(APPEND HEADER_FILES ${SOURCE_FILE})
        endif()
    endforeach()

    foreach(METAL_FILE ${METAL_FILES})
        get_filename_component(METAL_NAME ${METAL_FILE} NAME_WE)
        set(AIR_FILE "${CMAKE_BINARY_DIR}/${METAL_NAME}.air")

        set(ALL_DEPENDENCIES ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE})
        foreach(HEADER_FILE ${HEADER_FILES})
            list(APPEND ALL_DEPENDENCIES ${CMAKE_CURRENT_SOURCE_DIR}/${HEADER_FILE})
        endforeach()

        add_custom_command(
            OUTPUT ${AIR_FILE}
            COMMAND ${CMAKE_COMMAND} -E env DEVELOPER_DIR=${METAL_DEVELOPER_DIR}
                    ${METAL_COMPILER} -sdk macosx metal ${METAL_FLAGS}
                    -c ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE}
                    -o ${AIR_FILE}
            DEPENDS ${ALL_DEPENDENCIES}
            COMMENT "Compiling Metal shader ${METAL_FILE} to ${AIR_FILE}"
            VERBATIM
        )
        list(APPEND AIR_FILES ${AIR_FILE})
    endforeach()

    # Link .air → .metallib
    set(METALLIB_FILE "${METALLIB_OUTPUT_DIR}/${TARGET_NAME}.metallib")
    add_custom_command(
        OUTPUT ${METALLIB_FILE}
        COMMAND ${CMAKE_COMMAND} -E env DEVELOPER_DIR=${METAL_DEVELOPER_DIR}
                ${METAL_COMPILER} -sdk macosx metallib ${AIR_FILES}
                -o ${METALLIB_FILE}
        DEPENDS ${AIR_FILES}
        COMMENT "Linking Metal library ${METALLIB_FILE}"
        VERBATIM
    )

    # Embed metallib header (unchanged)
    set(METALLIB_HEADER "${CMAKE_BINARY_DIR}/${TARGET_NAME}_metallib.h")
    set(METALLIB_TO_HEADER_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/metallib_to_header.py")
    add_custom_command(
        OUTPUT ${METALLIB_HEADER}
        COMMAND ${Python_EXECUTABLE} ${METALLIB_TO_HEADER_SCRIPT} ${METALLIB_FILE} ${METALLIB_HEADER} ${TARGET_NAME}
        DEPENDS ${METALLIB_FILE} ${METALLIB_TO_HEADER_SCRIPT}
        COMMENT "Generating embedded Metal library header ${METALLIB_HEADER}"
        VERBATIM
    )
    add_custom_target(${TARGET_NAME}_metallib ALL DEPENDS ${METALLIB_FILE} ${METALLIB_HEADER})
    add_dependencies(${TARGET_NAME} ${TARGET_NAME}_metallib)
    target_include_directories(${TARGET_NAME} PRIVATE ${CMAKE_BINARY_DIR})
    target_compile_definitions(${TARGET_NAME} PRIVATE
        EMBEDDED_METALLIB_HEADER="${TARGET_NAME}_metallib.h"
        EMBEDDED_METALLIB_NAMESPACE=${TARGET_NAME}_metal
    )
endfunction()