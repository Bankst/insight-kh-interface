# cmake/libopencm3-stm32.cmake
include(FetchContent)

# ---------------------------------------------------------------------------
# Fetch libopencm3
# ---------------------------------------------------------------------------
FetchContent_Declare(libopencm3
  GIT_REPOSITORY https://github.com/libopencm3/libopencm3
  GIT_TAG master
)
FetchContent_MakeAvailable(libopencm3)
FetchContent_GetProperties(libopencm3)

# ---------------------------------------------------------------------------
# Build libopencm3 static library for the selected STM32 family
# ---------------------------------------------------------------------------
add_custom_command(
  OUTPUT ${libopencm3_SOURCE_DIR}/lib/libopencm3_stm32${CHIP_BASE_LOWER}.a
  COMMAND make TARGETS=stm32/${CHIP_BASE_LOWER}
  WORKING_DIRECTORY ${libopencm3_SOURCE_DIR}
  DEPENDS ${libopencm3_SOURCE_DIR}/Makefile
  COMMENT "Building libopencm3 for stm32${CHIP_BASE_LOWER}"
)

add_custom_target(libopencm3
  DEPENDS ${libopencm3_SOURCE_DIR}/lib/libopencm3_stm32${CHIP_BASE_LOWER}.a
)

# ---------------------------------------------------------------------------
# Import the built static library as a CMake target
# ---------------------------------------------------------------------------
add_library(${CHIP_TARGET} STATIC IMPORTED)
set_property(TARGET ${CHIP_TARGET} PROPERTY INTERFACE_INCLUDE_DIRECTORIES
  ${libopencm3_SOURCE_DIR}/include
)
set_property(TARGET ${CHIP_TARGET} PROPERTY IMPORTED_LOCATION
  ${libopencm3_SOURCE_DIR}/lib/libopencm3_stm32${CHIP_BASE_LOWER}.a
)
add_dependencies(${CHIP_TARGET} libopencm3)
target_link_directories(${CHIP_TARGET} INTERFACE ${libopencm3_SOURCE_DIR}/lib)

# ---------------------------------------------------------------------------
# Use libopencm3's genlink.py to determine flags and linker script params
# ---------------------------------------------------------------------------
set(GENLINK_PY "${libopencm3_SOURCE_DIR}/scripts/genlink.py")
set(DEVICES_DATA "${libopencm3_SOURCE_DIR}/ld/devices.data")

# ---------------------------------------------------------------------------
# Run genlink.py to extract MCU details from libopencm3 devices.data
# ---------------------------------------------------------------------------
set(GENLINK_PY "${libopencm3_SOURCE_DIR}/scripts/genlink.py")
set(DEVICES_DATA "${libopencm3_SOURCE_DIR}/ld/devices.data")

function(genlink_get VAR FIELD)
  # Build the command list clearly (for logging and execution)
  set(_cmd python3 "${GENLINK_PY}" "${DEVICES_DATA}" "${CHIP_FULL_NAME}" "${FIELD}")
  execute_process(
    COMMAND ${_cmd}
    OUTPUT_VARIABLE _out
    ERROR_VARIABLE _err
    RESULT_VARIABLE _res
    OUTPUT_STRIP_TRAILING_WHITESPACE
    WORKING_DIRECTORY "${libopencm3_SOURCE_DIR}"
  )

  if(NOT _res EQUAL 0)
    message(WARNING
      "genlink.py failed for mode=${FIELD} (device='${CHIP_FULL_NAME}')\n"
      "Exit code: ${_res}\n"
      "stderr: ${_err}"
    )
  elseif("${_out}" STREQUAL "")
    message(WARNING
      "genlink.py produced no output for mode=${FIELD} (device='${CHIP_FULL_NAME}')"
    )
  else()
    #message(STATUS "genlink.py output for ${FIELD}: ${_out}")
  endif()

  set(${VAR} "${_out}" PARENT_SCOPE)
endfunction()

# Query genlink metadata
genlink_get(GENLINK_FAMILY "FAMILY")
genlink_get(GENLINK_SUBFAMILY "SUBFAMILY")
genlink_get(GENLINK_CPU "CPU")
genlink_get(GENLINK_FPU "FPU")
genlink_get(GENLINK_CPPFLAGS "CPPFLAGS")
genlink_get(GENLINK_DEFS "DEFS")

# message(STATUS "libopencm3 genlink summary:")
# message(STATUS "  FAMILY    = ${GENLINK_FAMILY}")
# message(STATUS "  SUBFAMILY = ${GENLINK_SUBFAMILY}")
# message(STATUS "  CPU       = ${GENLINK_CPU}")
# message(STATUS "  FPU       = ${GENLINK_FPU}")
# message(STATUS "  CPPFLAGS  = ${GENLINK_CPPFLAGS}")
# message(STATUS "  DEFS      = ${GENLINK_DEFS}")


# ---------------------------------------------------------------------------
# Apply CPU/FPU/Thumb compile flags
# ---------------------------------------------------------------------------
set(ARCH_FLAGS "-mcpu=${GENLINK_CPU}")
if(GENLINK_CPU MATCHES "cortex-m[0-9]+")
  list(APPEND ARCH_FLAGS "-mthumb")
endif()

if(GENLINK_FPU STREQUAL "soft")
  list(APPEND ARCH_FLAGS "-msoft-float")
elseif(GENLINK_FPU STREQUAL "hard-fpv4-sp-d16")
  list(APPEND ARCH_FLAGS "-mfloat-abi=hard" "-mfpu=fpv4-sp-d16")
elseif(GENLINK_FPU STREQUAL "hard-fpv5-d16")
  list(APPEND ARCH_FLAGS "-mfloat-abi=hard" "-mfpu=fpv5-d16")
elseif(GENLINK_FPU STREQUAL "hard-fpv5-sp-d16")
  list(APPEND ARCH_FLAGS "-mfloat-abi=hard" "-mfpu=fpv5-sp-d16")
else()
  message(WARNING "No match for the FPU flags (${GENLINK_FPU})")
endif()

# ---------------------------------------------------------------------------
# Generate linker script
# ---------------------------------------------------------------------------
# Inputs
set(GENLINK_PY "${libopencm3_SOURCE_DIR}/scripts/genlink.py")
set(DEVICES_DATA "${libopencm3_SOURCE_DIR}/ld/devices.data")
set(LDS_TEMPLATE "${libopencm3_SOURCE_DIR}/ld/linker.ld.S")
set(GENERATED_LD "${CMAKE_BINARY_DIR}/generated.${CHIP_FULL_NAME}.ld")

# Get the DEFS from genlink.py
execute_process(
  COMMAND python3 "${GENLINK_PY}" "${DEVICES_DATA}" "${CHIP_FULL_NAME}" "DEFS"
  OUTPUT_VARIABLE GENLINK_DEFS
  OUTPUT_STRIP_TRAILING_WHITESPACE
  WORKING_DIRECTORY "${libopencm3_SOURCE_DIR}"
)

if(GENLINK_DEFS STREQUAL "")
  message(FATAL_ERROR "genlink.py returned empty DEFS for ${CHIP_FULL_NAME}")
endif()

# Convert the space-separated -D… string into a proper CMake list
#    (IMPORTANT: otherwise gcc gets one big arg and ignores the defines)
set(GENLINK_DEFS_LIST "${GENLINK_DEFS}")
separate_arguments(GENLINK_DEFS_LIST NATIVE_COMMAND "${GENLINK_DEFS}")

# Make ARCH_FLAGS a proper list
if(NOT ARCH_FLAGS_AS_LIST_DONE)
  set(_ARCH_FLAGS "${ARCH_FLAGS}")
  separate_arguments(_ARCH_FLAGS)
  set(ARCH_FLAGS_AS_LIST_DONE ON CACHE INTERNAL "done")
endif()

# string(JOIN " " _cmd_line
#   "${CMAKE_C_COMPILER}"
#   -x assembler-with-cpp
#   ${_ARCH_FLAGS}
#   ${GENLINK_DEFS_LIST}
#   -P -E "${LDS_TEMPLATE}" -o "${GENERATED_LD}"
# )
# message(STATUS "LDS generate command:\n  ${_cmd_line}")

add_custom_command(
  OUTPUT "${GENERATED_LD}"
  COMMAND "${CMAKE_C_COMPILER}" -x assembler-with-cpp
          ${_ARCH_FLAGS}
          ${GENLINK_DEFS_LIST}
          -P -E "${LDS_TEMPLATE}" -o "${GENERATED_LD}"
  DEPENDS "${LDS_TEMPLATE}" "${GENLINK_PY}" "${DEVICES_DATA}"
  WORKING_DIRECTORY "${libopencm3_SOURCE_DIR}"
  COMMENT "Generating linker script for ${CHIP_FULL_NAME}"
)

add_custom_target(genlink_ld ALL DEPENDS "${GENERATED_LD}")
target_link_options(${CHIP_TARGET} INTERFACE "-T${GENERATED_LD}")


# ---------------------------------------------------------------------------
# Attach compile and link flags to imported library target
# ---------------------------------------------------------------------------
target_compile_definitions(${CHIP_TARGET} INTERFACE ${CPPFLAGS})
target_compile_options(${CHIP_TARGET} INTERFACE
  ${ARCH_FLAGS} # mcpu, thumb, mfpu
  -Wno-psabi
  -fdata-sections
  -ffunction-sections
  $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
  $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
  $<$<COMPILE_LANGUAGE:CXX>:-fno-unwind-tables>
  $<$<COMPILE_LANGUAGE:CXX>:-fno-asynchronous-unwind-tables>
  $<$<C_COMPILER_ID:GNU>:--specs=nosys.specs>
  $<$<C_COMPILER_ID:GNU>:--specs=nano.specs>
)
target_link_options(${CHIP_TARGET} INTERFACE 
  ${ARCH_FLAGS} # mcpu, thumb, mfpu
  -nostartfiles
  -Wl,--gc-sections
  $<$<C_COMPILER_ID:GNU>:--specs=nosys.specs>
  $<$<C_COMPILER_ID:GNU>:--specs=nano.specs>
)

target_compile_definitions(${CHIP_TARGET} INTERFACE -DSTM32${CHIP_BASE_UPPER})

# ---------------------------------------------------------------------------
# Add flash programming utility via OpenOCD
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper for linking the generated linker script explicitly
# ---------------------------------------------------------------------------
function(stm32_add_linker_script TARGET ACCESS FILE)
  target_link_options(${TARGET} ${ACCESS} "-T${FILE}")
endfunction()
