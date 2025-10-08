cmake_minimum_required(VERSION 3.15 FATAL_ERROR)
set(CMAKE_TOOLCHAIN_FILE cmake/toolchain-arm-none-eabi-gcc.cmake)
project(insight-kh VERSION 0.1.0 LANGUAGES CXX C ASM)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CHIP_TARGET "stm32g0b1")
set(CHIP_BASE_UPPER "G0")
set(CHIP_BASE_LOWER "g0")
set(CHIP_CORTEX "m0")
include(cmake/libopencm3-stm32x.cmake)

set(EXEC_NAME "mcuapp")

add_executable(${EXEC_NAME} src/main.cpp)
target_link_libraries(${EXEC_NAME} ${CHIP_TARGET})
set_property(TARGET ${EXEC_NAME} PROPERTY CXX_STANDARD 17)
stm32_add_linker_script(${EXEC_NAME} PRIVATE STM32G0B1RETX_FLASH.ld)
stm32_add_flash_targets(${EXEC_NAME})