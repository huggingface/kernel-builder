# Metal shader compilation function
function(compile_metal_shaders TARGET_NAME METAL_SOURCES)
    # Find the Metal compiler
    find_program(METAL_COMPILER xcrun REQUIRED)
    
    # Set Metal compiler flags
    set(METAL_FLAGS "-std=metal3.0" "-O2")
    
    # Output directory for compiled metallib
    set(METALLIB_OUTPUT_DIR "${CMAKE_BINARY_DIR}/metallib")
    file(MAKE_DIRECTORY ${METALLIB_OUTPUT_DIR})
    
    # Separate .metal files from .h files and compile .metal files to .air
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
        
        # Include header files as dependencies
        set(ALL_DEPENDENCIES ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE})
        foreach(HEADER_FILE ${HEADER_FILES})
            list(APPEND ALL_DEPENDENCIES ${CMAKE_CURRENT_SOURCE_DIR}/${HEADER_FILE})
        endforeach()
        
        add_custom_command(
            OUTPUT ${AIR_FILE}
            COMMAND ${METAL_COMPILER} -sdk macosx metal ${METAL_FLAGS}
                    -c ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE}
                    -o ${AIR_FILE}
            DEPENDS ${ALL_DEPENDENCIES}
            COMMENT "Compiling Metal shader ${METAL_FILE} to ${AIR_FILE}"
            VERBATIM
        )
        
        list(APPEND AIR_FILES ${AIR_FILE})
    endforeach()
    
    # Link all .air files into a single .metallib
    set(METALLIB_FILE "${METALLIB_OUTPUT_DIR}/${TARGET_NAME}.metallib")
    add_custom_command(
        OUTPUT ${METALLIB_FILE}
        COMMAND ${METAL_COMPILER} -sdk macosx metallib ${AIR_FILES}
                -o ${METALLIB_FILE}
        DEPENDS ${AIR_FILES}
        COMMENT "Linking Metal library ${METALLIB_FILE}"
        VERBATIM
    )
    
    # Generate C++ header with embedded metallib data
    set(METALLIB_HEADER "${CMAKE_BINARY_DIR}/${TARGET_NAME}_metallib.h")
    set(METALLIB_TO_HEADER_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/metallib_to_header.py")
    
    add_custom_command(
        OUTPUT ${METALLIB_HEADER}
        COMMAND ${Python3_EXECUTABLE} ${METALLIB_TO_HEADER_SCRIPT} ${METALLIB_FILE} ${METALLIB_HEADER} ${TARGET_NAME}
        DEPENDS ${METALLIB_FILE} ${METALLIB_TO_HEADER_SCRIPT}
        COMMENT "Generating embedded Metal library header ${METALLIB_HEADER}"
        VERBATIM
    )
    
    # Create a custom target for the metallib
    add_custom_target(${TARGET_NAME}_metallib ALL DEPENDS ${METALLIB_FILE} ${METALLIB_HEADER})
    
    # Add dependency to main target
    add_dependencies(${TARGET_NAME} ${TARGET_NAME}_metallib)
    
    # Add the generated header to include directories
    target_include_directories(${TARGET_NAME} PRIVATE ${CMAKE_BINARY_DIR})
    
    # Pass the metallib header and namespace as compile definitions
    target_compile_definitions(${TARGET_NAME} PRIVATE 
        EMBEDDED_METALLIB_HEADER="${TARGET_NAME}_metallib.h"
        EMBEDDED_METALLIB_NAMESPACE=${TARGET_NAME}_metal
    )
endfunction()