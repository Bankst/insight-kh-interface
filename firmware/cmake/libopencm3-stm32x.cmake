include(FetchContent)
FetchContent_Declare(libopencm3
  GIT_REPOSITORY https://github.com/libopencm3/libopencm3
  GIT_TAG master
)
FetchContent_MakeAvailable(libopencm3)
FetchContent_GetProperties(libopencm3)

# create a target to build libopencm3 -- only for the target we need
add_custom_target(libopencm3 make TARGETS=stm32/${CHIP_BASE_LOWER} WORKING_DIRECTORY ${libopencm3_SOURCE_DIR})

# Create a specific CPU target with the appropriate options etc
add_library(${CHIP_TARGET} STATIC IMPORTED)
set_property(TARGET ${CHIP_TARGET} PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${libopencm3_SOURCE_DIR}/include)
set_property(TARGET ${CHIP_TARGET} PROPERTY IMPORTED_LOCATION ${libopencm3_SOURCE_DIR}/lib/libopencm3_stm32${CHIP_BASE_LOWER}.a)
add_dependencies(${CHIP_TARGET} libopencm3)
target_link_directories(${CHIP_TARGET} INTERFACE ${libopencm3_SOURCE_DIR}/lib)

target_compile_definitions(${CHIP_TARGET} INTERFACE -DSTM32${CHIP_BASE_UPPER})

set(COMPILE_OPTIONS 
  --static
  -nostartfiles
  -fno-common
  -mcpu=cortex-${CHIP_CORTEX}
  -mthumb
  # -mfloat-abi=hard
  -mfpu=fpv5-d16
)
target_compile_options(${CHIP_TARGET} INTERFACE ${COMPILE_OPTIONS})
target_link_options(${CHIP_TARGET} INTERFACE ${COMPILE_OPTIONS})


function(stm32_add_flash_targets TARGET)
  add_custom_target(${TARGET}-stlink-flash
    bash -c "openocd -f /usr/share/openocd/scripts/interface/stlink-v2.cfg \
              -f /usr/share/openocd/scripts/target/stm32${CHIP_BASE_LOWER}x.cfg \
              -c 'reset_config none; program ${TARGET}.elf verify reset exit'"
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    DEPENDS ${TARGET}
    VERBATIM
  )
endfunction()