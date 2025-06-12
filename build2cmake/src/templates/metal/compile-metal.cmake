# Metal shader compilation function
function(compile_metal_shaders TARGET_NAME METAL_SOURCES)
    # Find the Metal compiler
    find_program(METAL_COMPILER xcrun REQUIRED)
    
    # Set Metal compiler flags
    set(METAL_FLAGS "-std=metal3.0" "-O2")
    
    # Output directory for compiled metallib
    set(METALLIB_OUTPUT_DIR "${CMAKE_BINARY_DIR}/metallib")
    file(MAKE_DIRECTORY ${METALLIB_OUTPUT_DIR})
    
    # Compile each .metal file to .air
    set(AIR_FILES)
    foreach(METAL_FILE ${METAL_SOURCES})
        get_filename_component(METAL_NAME ${METAL_FILE} NAME_WE)
        set(AIR_FILE "${CMAKE_BINARY_DIR}/${METAL_NAME}.air")
        
        add_custom_command(
            OUTPUT ${AIR_FILE}
            COMMAND ${METAL_COMPILER} -sdk macosx metal ${METAL_FLAGS}
                    -c ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE}
                    -o ${AIR_FILE}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${METAL_FILE}
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
    
    # Create a custom target for the metallib
    add_custom_target(${TARGET_NAME}_metallib ALL DEPENDS ${METALLIB_FILE})
    
    # Add dependency to main target
    add_dependencies(${TARGET_NAME} ${TARGET_NAME}_metallib)
    
    # Set property so we can access the metallib path later
    set_target_properties(${TARGET_NAME} PROPERTIES
        METALLIB_FILE ${METALLIB_FILE}
    )
    
    # Install the metallib
    install(FILES ${METALLIB_FILE}
            DESTINATION lib
            COMPONENT metal_shaders)
endfunction()