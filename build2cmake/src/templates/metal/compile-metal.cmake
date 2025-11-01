# Metal shader compilation function
function(compile_metal_shaders TARGET_NAME METAL_SOURCES)
    # Prefer Apple toolchain directly; fall back to /usr/bin/xcrun; last resort: any xcrun on PATH
    find_program(METAL_TOOL metal
        HINTS
            /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
            /Library/Developer/CommandLineTools/usr/bin
            /usr/bin
        NO_CACHE
    )
    find_program(METALLIB_TOOL metallib
        HINTS
            /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
            /Library/Developer/CommandLineTools/usr/bin
            /usr/bin
        NO_CACHE
    )
    find_program(APPLE_XCRUN /usr/bin/xcrun NO_CACHE)
    if(NOT METAL_TOOL OR NOT METALLIB_TOOL)
        if(NOT APPLE_XCRUN)
            # Last resort if absolutely necessary (may resolve to Nix wrapper)
            find_program(ANY_XCRUN xcrun)
        endif()
    endif()
    if(METAL_TOOL AND METALLIB_TOOL)
        set(USE_DIRECT_TOOLS TRUE)
    elseif(APPLE_XCRUN)
        set(USE_XCRUN ${APPLE_XCRUN})
    elseif(ANY_XCRUN)
        set(USE_XCRUN ${ANY_XCRUN})
    else()
        message(FATAL_ERROR "No Apple Metal toolchain found (metal/metallib or /usr/bin/xcrun).")
    endif()

    # Flags
    set(METAL_FLAGS "-std=metal3.2" "-O2")

    # Include dirs for <internal/...> in shaders
    set(METAL_INCLUDE_DIRS
        "${CMAKE_SOURCE_DIR}/gptoss_kernels/source/include"
        "${CMAKE_SOURCE_DIR}/gptoss_kernels/include"
        "${CMAKE_SOURCE_DIR}/."
    )
    foreach(INC ${METAL_INCLUDE_DIRS})
        list(APPEND METAL_FLAGS "-I${INC}")
    endforeach()

    # Output dir for metallib
    set(METALLIB_OUTPUT_DIR "${CMAKE_BINARY_DIR}/metallib")
    file(MAKE_DIRECTORY ${METALLIB_OUTPUT_DIR})

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

    # Compile .metal → .air
    foreach(METAL_FILE ${METAL_FILES})
        get_filename_component(METAL_NAME ${METAL_FILE} NAME_WE)
        set(AIR_FILE "${CMAKE_BINARY_DIR}/${METAL_NAME}.air")

        set(ALL_DEPENDENCIES ${CMAKE_SOURCE_DIR}/${METAL_FILE})
        foreach(HEADER_FILE ${HEADER_FILES})
            list(APPEND ALL_DEPENDENCIES ${CMAKE_SOURCE_DIR}/${HEADER_FILE})
        endforeach()

        if(USE_DIRECT_TOOLS)
            add_custom_command(
                OUTPUT ${AIR_FILE}
                COMMAND ${METAL_TOOL} ${METAL_FLAGS}
                        -c ${CMAKE_SOURCE_DIR}/${METAL_FILE}
                        -o ${AIR_FILE}
                DEPENDS ${ALL_DEPENDENCIES}
                COMMENT "Compiling Metal shader ${METAL_FILE} to ${AIR_FILE}"
                VERBATIM
            )
        else()
            add_custom_command(
                OUTPUT ${AIR_FILE}
                COMMAND ${USE_XCRUN} -sdk macosx metal ${METAL_FLAGS}
                        -c ${CMAKE_SOURCE_DIR}/${METAL_FILE}
                        -o ${AIR_FILE}
                DEPENDS ${ALL_DEPENDENCIES}
                COMMENT "Compiling Metal shader ${METAL_FILE} to ${AIR_FILE}"
                VERBATIM
            )
        endif()
        list(APPEND AIR_FILES ${AIR_FILE})
    endforeach()

    # Link .air → .metallib
    set(METALLIB_FILE "${METALLIB_OUTPUT_DIR}/${TARGET_NAME}.metallib")
    if(USE_DIRECT_TOOLS)
        add_custom_command(
            OUTPUT ${METALLIB_FILE}
            COMMAND ${METALLIB_TOOL} ${AIR_FILES} -o ${METALLIB_FILE}
            DEPENDS ${AIR_FILES}
            COMMENT "Linking Metal library ${METALLIB_FILE}"
            VERBATIM
        )
    else()
        add_custom_command(
            OUTPUT ${METALLIB_FILE}
            COMMAND ${USE_XCRUN} -sdk macosx metallib ${AIR_FILES} -o ${METALLIB_FILE}
            DEPENDS ${AIR_FILES}
            COMMENT "Linking Metal library ${METALLIB_FILE}"
            VERBATIM
        )
    endif()

    # Embed metallib
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