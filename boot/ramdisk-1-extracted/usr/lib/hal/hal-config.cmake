#
# Copyright (c) 2021 Amazon.com, Inc. or its affiliates.  All rights reserved.
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

# - hal config mode
#
# Defines the following variables:
#  hal_FOUND        - true
#  hal_VERSION      - version of the platform library found, e.g. 0.2
#  hal_INCLUDE_DIRS - header directories with which to compile
#  hal_LINKER_FLAGS - flags that must be passed to the linker
#  hal_LIBRARIES    - names of the libraries with which to link
#  hal_LIBRARY_DIRS - directories in which the libraries are situated
#
# propagate these properties from one build system to the other

set(hal_VERSION  "1.0.0")

get_filename_component(_hal_rootdir ${CMAKE_CURRENT_LIST_DIR}/../ ABSOLUTE)

find_path(hal_INCLUDE_DIRS hal/hal.h)
set (hal_INCLUDE_DIRS "${_hal_rootdir}/include" "${_hal_rootdir}/include/hal")
set (hal_LIBRARY_DIRS "${_hal_rootdir}" "${_hal_rootdir}/modules/boot_control")
set (hal_LINKER_FLAGS "")
set (hal_CONFIG_VARS "")
find_library (hal_LIBRARY hal)

set (hal_LIBRARY "-L${_hal_rootdir} -lhal")
set (hal_LIBRARIES ${hal_LIBRARY} "dl")

mark_as_advanced (hal_LIBRARY)

# add the library as a target, so that other things in the project including
# this file may depend on it and get rebuild if this library changes.
add_library (hal UNKNOWN IMPORTED)
set_property (TARGET hal PROPERTY IMPORTED_LOCATION "${hal_LIBRARY}")
