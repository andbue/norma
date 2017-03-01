# Copyright (c) 2012 - 2015, Lars Bilke
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#
#
# 2012-01-31, Lars Bilke
# - Enable Code Coverage
#
# 2013-09-17, Joakim Söderberg
# - Added support for Clang.
# - Some additional usage instructions.
#
# 2017-03-01, Florian Petran
# - changed the main macro to allow for multiple test binaries.
# - this module now adds a global coverage target which does all the pre-run cleaning
#   and post-run converting. previously each target did that by itself, so the
#   coverage reports weren't combined
#
# USAGE:

# 0. (Mac only) If you use Xcode 5.1 make sure to patch geninfo as described here:
#      http://stackoverflow.com/a/22404544/80480
#
# 1. Copy this file into your cmake modules path.
#
# 2. Add the following line to your CMakeLists.txt:
#      INCLUDE(CodeCoverage)
#
# 3. Set compiler flags to turn off optimization and enable coverage:
#    SET(CMAKE_CXX_FLAGS "-g -O0 -fprofile-arcs -ftest-coverage")
#    SET(CMAKE_C_FLAGS "-g -O0 -fprofile-arcs -ftest-coverage")
#
# 3. Use the function SETUP_TARGET_FOR_COVERAGE to create a custom make target
#    which runs your test executable and produces a lcov code coverage report:
#    Example:
#    SETUP_TARGET_FOR_COVERAGE(
#            test_driver         # Name of the test driver executable that runs the tests.
#                           # NOTE! This should always have a ZERO as exit code
#                           # otherwise the coverage generation will not complete.
#            )
#
# 4. Build a Debug build:
#    cmake -DCMAKE_BUILD_TYPE=Debug ..
#    make
#    make coverage
#
#

# Check prereqs
FIND_PROGRAM( GCOV_PATH gcov )
FIND_PROGRAM( LCOV_PATH lcov )
FIND_PROGRAM( GENHTML_PATH genhtml )
FIND_PROGRAM( GCOVR_PATH gcovr PATHS ${CMAKE_SOURCE_DIR}/tests)

IF(NOT GCOV_PATH)
   MESSAGE(FATAL_ERROR "gcov not found! Aborting...")
ENDIF() # NOT GCOV_PATH

IF("${CMAKE_CXX_COMPILER_ID}" MATCHES "(Apple)?[Cc]lang")
   IF("${CMAKE_CXX_COMPILER_VERSION}" VERSION_LESS 3)
      MESSAGE(FATAL_ERROR "Clang version must be 3.0.0 or greater! Aborting...")
   ENDIF()
ELSEIF(NOT CMAKE_COMPILER_IS_GNUCXX)
   MESSAGE(FATAL_ERROR "Compiler is not GNU gcc! Aborting...")
ENDIF() # CHECK VALID COMPILER

SET(CMAKE_CXX_FLAGS_COVERAGE
    "-g -O0 --coverage -fprofile-arcs -ftest-coverage"
    CACHE STRING "Flags used by the C++ compiler during coverage builds."
    FORCE )
SET(CMAKE_C_FLAGS_COVERAGE
    "-g -O0 --coverage -fprofile-arcs -ftest-coverage"
    CACHE STRING "Flags used by the C compiler during coverage builds."
    FORCE )
SET(CMAKE_EXE_LINKER_FLAGS_COVERAGE
    ""
    CACHE STRING "Flags used for linking binaries during coverage builds."
    FORCE )
SET(CMAKE_SHARED_LINKER_FLAGS_COVERAGE
    ""
    CACHE STRING "Flags used by the shared libraries linker during coverage builds."
    FORCE )
MARK_AS_ADVANCED(
    CMAKE_CXX_FLAGS_COVERAGE
    CMAKE_C_FLAGS_COVERAGE
    CMAKE_EXE_LINKER_FLAGS_COVERAGE
    CMAKE_SHARED_LINKER_FLAGS_COVERAGE )

IF ( NOT (CMAKE_BUILD_TYPE STREQUAL "Debug" OR CMAKE_BUILD_TYPE STREQUAL "Coverage"))
  MESSAGE( WARNING "Code coverage results with an optimized (non-Debug) build may be misleading" )
ENDIF() # NOT CMAKE_BUILD_TYPE STREQUAL "Debug"

# _output: where to put coverage report
# _testsrc: directory where the test sources live
FUNCTION(SETUP_COVERAGE _output _testsrc)
    SET(COVERAGE_OUTPUT_DIR ${_output} CACHE INTERNAL "COVERAGE_OUTPUT_DIR")
    SET(COVERAGE_TESTS_SRC ${_testsrc} CACHE INTERNAL "COVERAGE_TESTS_SRC")
ENDFUNCTION()

# global coverage target
ADD_CUSTOM_TARGET(coverage)
ADD_CUSTOM_TARGET(coverage_setup
                  COMMAND ${LCOV_PATH} --directory . --zerocounters
                  COMMENT "Resetting code coverage counters to zero."
                  COMMENT "Processing code coverage counters and generating report.")
ADD_DEPENDENCIES(coverage coverage_setup)
ADD_CUSTOM_COMMAND(TARGET coverage POST_BUILD
    COMMAND ${LCOV_PATH} --remove "${COVERAGE_OUTPUT_DIR}.info" '${COVERAGE_TESTS_SRC}/*' '/usr/*' --output-file "${COVERAGE_OUTPUT_DIR}.cleaned"
    COMMAND ${GENHTML_PATH} -o ${COVERAGE_OUTPUT_DIR} "${COVERAGE_OUTPUT_DIR}.cleaned"
    COMMAND ${CMAKE_COMMAND} -E remove "${COVERAGE_OUTPUT_DIR}.info" "${COVERAGE_OUTPUT_DIR}.cleaned"
    COMMENT "Open ./${COVERAGE_OUTPUT_DIR}/index.html in your browser to view the coverage report."
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Param _testrunner     The name of the target which runs the tests.
#                  MUST return ZERO always, even on errors.
#                  If not, no coverage report will be created!
# Optional fourth parameter is passed as arguments to _testrunner
#   Pass them in list form, e.g.: "-j;2" for -j 2
FUNCTION(SETUP_TARGET_FOR_COVERAGE _testrunner)

   IF(NOT LCOV_PATH)
      MESSAGE(FATAL_ERROR "lcov not found! Aborting...")
   ENDIF() # NOT LCOV_PATH

   IF(NOT GENHTML_PATH)
      MESSAGE(FATAL_ERROR "genhtml not found! Aborting...")
   ENDIF() # NOT GENHTML_PATH

   SEPARATE_ARGUMENTS(test_command UNIX_COMMAND "${_testrunner}")

   # Setup target
   ADD_CUSTOM_TARGET("${_testrunner}_coverage"
      # Run tests
      COMMAND ${test_command} ${ARGV3}
      # Capturing lcov counters and generating report
      COMMAND ${LCOV_PATH} -q --directory . --capture --output-file ${COVERAGE_OUTPUT_DIR}.info
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
   )
   ADD_DEPENDENCIES(coverage "${_testrunner}_coverage")
   ADD_DEPENDENCIES("${_testrunner}_coverage" coverage_setup)

ENDFUNCTION() # SETUP_TARGET_FOR_COVERAGE

