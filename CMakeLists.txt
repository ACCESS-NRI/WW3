# Copyright ACCESS-NRI and contributors. See the top-level LICENSE file for details.

cmake_minimum_required(VERSION 3.19)

#[==============================================================================[
#                         Basic project definition                              #
#]==============================================================================]

project(WW3
        DESCRIPTION "WAVEWATCH III numerical wave model"
        HOMEPAGE_URL https://github.com/ACCESS-NRI/WW3/
        LANGUAGES C Fortran)

#[==============================================================================[
#                                   Options                                     #
#]==============================================================================]

## List of switches
# to-do: make configurable 
list(APPEND switches "CESMCOUPLED" "DIST" "MPI" "PR1" "FLX4" "ST6" "STAB0" "LN1" "NL1" "BT1" "DB1" "MLIM" "TR0" "BS0" "RWND" "WNX1" "WNT0" "CRX1" "CRT0" "O0" "O1" "O2" "O3" "O4" "O5" "O6" "O7" "O14" "O15" "IS2" "REF0" "NOGRB" "IC3")

option(ACCESS3_WW3     "Use ACCESS3 dependencies and install ACCESS3 libraries" OFF)
option(OPENMP          "Enable OpenMP threading" OFF)
message(STATUS "  - ACCESS3_WW3   ${ACCESS3_WW3}")
message(STATUS "  - OPENMP        ${OPENMP}")

if(NOT ACCESS3_WW3)
  message(STATUS " - NOT ACCESS3_WW3: Building standalone ww3_shel for testing")
endif()

if(OPENMP)
  list(APPEND switches "OMPG")
endif()



#[==============================================================================[
#                           Project configuration                               #
#]==============================================================================]

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)
include(FortranLib)

# Common compiler flags and definitions
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fbacktrace -fconvert=big-endian -ffree-line-length-none -ffixed-line-length-none")
  if(${CMAKE_Fortran_COMPILER_VERSION} VERSION_GREATER_EQUAL 10)
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fallow-argument-mismatch")
  endif()
  set(CMAKE_Fortran_FLAGS_RELEASE "-O")
  set(CMAKE_Fortran_FLAGS_DEBUG "-g -Wall -Og -ffpe-trap=zero,overflow -fcheck=bounds")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -qno-opt-dynamic-align  -convert big_endian -assume byterecl -ftz -traceback -assume realloc_lhs -fp-model precise")
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2 -debug minimal")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g -check uninit -check bounds -check pointers -fpe0 -check noarg_temp_created")
else()
  message(WARNING "Fortran compiler with ID ${CMAKE_Fortran_COMPILER_ID} will be used with CMake default options")
endif()

if(CMAKE_C_COMPILER_ID MATCHES "GNU")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99")
  set(CMAKE_C_FLAGS_RELEASE "-O")
  set(CMAKE_C_FLAGS_DEBUG "-g -Wall -Og -fbacktrace -ffpe-trap=invalid,zero,overflow -fcheck=bounds")
elseif(CMAKE_C_COMPILER_ID MATCHES "Intel")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -traceback -qno-opt-dynamic-align -fp-model precise -std=gnu99")
  set(CMAKE_C_FLAGS_RELEASE "-O2 -debug minimal")
  set(CMAKE_C_FLAGS_DEBUG "-O0 -g")
else()
  message(WARNING "C compiler with ID ${CMAKE_C_COMPILER_ID} will be used with CMake default options")
endif()

## Global compile definitions
foreach(switch ${switches})
  add_compile_definitions(W3_${switch})
endforeach()

if ("CESMCOUPLED" IN_LIST switches)
  add_compile_definitions(CESMCOUPLED)
endif()

## Fortran modules path; currently this is simply set to be the include dir
set(CMAKE_INSTALL_MODULEDIR ${CMAKE_INSTALL_INCLUDEDIR}
  CACHE STRING
  "Fortran module installation path (Not a cmake native variable)"
)

#[==============================================================================[
#                              External packages                                #
#]==============================================================================]

find_package(MPI REQUIRED)

if(ACCESS3_WW3)
  find_package(Access3Share REQUIRED cdeps timing share nuopc_cap_share) 
  if(NOT TARGET ESMF::ESMF) #Access3Share probably already has ESMF with PUBLIC interface
    find_package(ESMF 8.3.0 MODULE REQUIRED)
  endif() 
endif()

if(NOT TARGET NetCDF::NetCDF_Fortran) #Access3Share probably already has NetCDF with PUBLIC interface
  find_package(NetCDF 4.7.3 MODULE REQUIRED Fortran)
endif()

if(OPENMP)
  find_package(OpenMP REQUIRED COMPONENTS Fortran)
endif()

#[==============================================================================[
#                             Main definitions                                  #
#]==============================================================================]

## WW3 library

set(SRC "${CMAKE_SOURCE_DIR}/model/src")

add_fortran_library(ww3lib mod STATIC)
target_include_directories(ww3lib PRIVATE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/model/src>)
target_compile_definitions(ww3lib PRIVATE ENDIANNESS="big_endian")
set_property(SOURCE ${SRC}/w3initmd.F90
  APPEND
  PROPERTY COMPILE_DEFINITIONS
  "__WW3_SWITCHES__=\'\'"
)
target_link_libraries(ww3lib PUBLIC NetCDF::NetCDF_Fortran)

if(ACCESS3_WW3)
  target_link_libraries(ww3lib PUBLIC ESMF::ESMF PIO::PIO_C)
endif()

if(OpenMP_Fortran_FOUND)
  target_link_libraries(ww3lib PUBLIC OpenMP::OpenMP_Fortran)
endif()

# Process switches and get list of extra source files
include(${CMAKE_CURRENT_SOURCE_DIR}/model/src/cmake/check_switches.cmake)
check_switches("${switches}" switch_files)
message(VERBOSE "WW3 switch files: ${switch_files}")

include(${CMAKE_CURRENT_SOURCE_DIR}/model/src/cmake/src_list.cmake)

if(ACCESS3_WW3)
  list(APPEND ftn_src ${nuopc_mesh_cap_src})
endif()

list(APPEND ftn_src ${switch_files})

foreach(file ${ftn_src})
    list(APPEND srcfiles "${CMAKE_CURRENT_SOURCE_DIR}/model/src/${file}")
endforeach()

target_sources(ww3lib PRIVATE ${srcfiles}) 

## Utilities
# Always build utilities:
set(utility_apps ww3_grid ww3_strt ww3_outf ww3_ounf ww3_ounp)
if(NOT ACCESS3_WW3)
  # A generic WW3 "shell" for testing
  list(APPEND utility_apps ww3_shel)
endif()
  #to-do: confim when other utilities are needed:
  # ww3_bound ww3_outp ww3_trck ww3_grib
  # ww3_gint gx_outf gx_outp ww3_uprstr ww3_prep ww3_gspl ww3_multi ww3_systrk
  # ww3_ounf ww3_ounp ww3_bounc ww3_trnc ww3_prnc

foreach(program ${utility_apps})
  add_executable(${program} ${SRC}/${program}.F90)
  set_target_properties(${program} PROPERTIES
    LINKER_LANGUAGE Fortran
    OUTPUT_NAME ${program}
  )
  target_link_libraries(${program} PRIVATE ww3lib)
endforeach()

# ww3_ounf has en extra file
target_sources(ww3_ounf PRIVATE
  ${SRC}/w3ounfmetamd.F90
)

#[==============================================================================[
#                             Install and Export                                  #
#]==============================================================================]

## Library
if(ACCESS3_WW3)
  set_target_properties(ww3lib PROPERTIES
    OUTPUT_NAME access-ww3lib
    EXPORT_NAME ww3lib
  )
  install(TARGETS ww3lib
    EXPORT Ww3libTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT AccessWW3Cmeps_RunTime NAMELINK_COMPONENT AccessWW3Cmeps_Development
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT AccessWW3Cmeps_Development
  )
  # Fortran module files are a special case, as currently there is no standard
  # way of handling them in CMake
  target_include_directories(ww3lib PUBLIC "$<INSTALL_INTERFACE:${CMAKE_INSTALL_MODULEDIR}/access-ww3>")
  get_target_property(ww3_moddir ww3lib Fortran_MODULE_DIRECTORY)
  install(FILES ${ww3_moddir}/wav_comp_nuopc.mod
    DESTINATION ${CMAKE_INSTALL_MODULEDIR}/access-ww3
    COMPONENT AccessWW3Cmeps_Development
  )
  install(EXPORT Ww3libTargets
    FILE Ww3libTargets.cmake
    NAMESPACE Access3::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Ww3lib
  )

  # Make sure the dependencies get exported too
  configure_package_config_file(
    cmake/Access3Ww3libConfig.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/Ww3libConfig.cmake"
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Ww3lib
  )
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/Ww3libConfig.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Ww3lib
    COMPONENT AccessWW3Cmeps_Development 
  )
endif()

## Utilities
install(TARGETS ${utility_apps}
RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

