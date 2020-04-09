# ##################################################################################################
# Determine and set the Fortran compiler flags we want
# ##################################################################################################
# https://github.com/SethMMorton/cmake_fortran_template

# ##################################################################################################
# Make sure that the default build type is RELEASE if not specified.
# ##################################################################################################
include(${CMAKE_MODULE_PATH}/SetCompileFlag.cmake)

# Make sure the build type is uppercase
string(TOUPPER "${CMAKE_BUILD_TYPE}" BT)

message(STATUS "Build type: ${BT}")

if(BT STREQUAL "RELEASE")
  set(CMAKE_BUILD_TYPE
      RELEASE
      CACHE STRING "Choose the type of build, options are DEBUG or RELEASE" FORCE)
elseif(BT STREQUAL "DEBUG")
  set(CMAKE_BUILD_TYPE
      DEBUG
      CACHE STRING "Choose the type of build, options are DEBUG or RELEASE" FORCE)
elseif(NOT BT)
  set(CMAKE_BUILD_TYPE
      RELEASE
      CACHE STRING "Choose the type of build, options are DEBUG or RELEASE" FORCE)
  message(STATUS "CMAKE_BUILD_TYPE not given, defaulting to RELEASE")
else()
  message(FATAL_ERROR "CMAKE_BUILD_TYPE not valid, choices are DEBUG or RELEASE")
endif(BT STREQUAL "RELEASE")

# gfortran
if(CMAKE_Fortran_COMPILER_ID STREQUAL GNU)

  # There is some bug where -march=native doesn't work on Mac
  if(APPLE)
    set(GNUNATIVE "-mtune=native")
  else()
    set(GNUNATIVE "-march=native")
  endif()

  set(CMAKE_Fortran_FLAGS "-cpp -std=f2018 -ffree-line-length-none -fcoarray=lib")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ${Coarray_COMPILE_OPTIONS}")
  set(CMAKE_Fortran_FLAGS_DEBUG
      "-O0 -g \
 -Wall -Wextra -Wpedantic -Wconversion \
 -fimplicit-none -fbacktrace \
 -fcheck=all -ffpe-trap=zero,overflow,invalid,underflow -finit-real=nan")

  set(CMAKE_Fortran_FLAGS_RELEASE
      "-O3 -funroll-loops -finline-functions -floop-parallelize-all -ftree-parallelize-loops=6 ${GNUNATIVE}"
  )

  if(ENABLE_PROFILING)
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -pg -g")
  endif()

endif()

# ifort
if(CMAKE_Fortran_COMPILER_ID STREQUAL Intel)

  # if(SERIAL_BUILD) set(IFORT_COARRAY "-coarray=single") elseif(SHARED_MEMORY) set(IFORT_COARRAY
  # "-coarray=shared") elseif(DISTRIBUTED_MEMORY) set(IFORT_COARRAY "-coarray=distributed") endif()

  set(IFORT_FLAGS
      "-fpp -fp-model precise -fp-model except -diag-disable 5268 -diag-disable 8770 ${Coarray_COMPILE_OPTIONS}"
  )

  # Fortran 2018 standards check based on the version
  if(CMAKE_Fortran_COMPILER_VERSION VERSION_LESS 19.0.3)
    set(CMAKE_Fortran_FLAGS "-stand f15 ${IFORT_FLAGS}")
  else()
    set(CMAKE_Fortran_FLAGS "-stand f18 ${IFORT_FLAGS}")
  endif()

  if(ENABLE_PROFILING)
    set(CMAKE_Fortran_FLAGS
        "${CMAKE_Fortran_FLAGS} -p -g -qopt-report-phase=all -qopt-report-annotate-position=both -qopt-report=5"
    )
  endif()

  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g -warn all -debug all -traceback -fpe-all=0 -check all")
  set(CMAKE_Fortran_FLAGS_RELEASE " -O3 -xHost -ipo -parallel -mtune=${TARGET_ARCHITECTURE}")
endif()
