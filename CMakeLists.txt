cmake_minimum_required(VERSION 3.18)

project(ksmppd
    VERSION 1.4.4
    DESCRIPTION "Kurt's SMPP Daemon (SMPP server for Kannel)"
    HOMEPAGE_URL "https://github.com/kneodev/ksmppd"
    LANGUAGES C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
# gwlib relies on GNU extensions
set(CMAKE_C_EXTENSIONS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

include(GNUInstallDirs)

# --- Dependencies -----------------------------------------------------------

find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBEVENT REQUIRED IMPORTED_TARGET libevent>=2.0)
pkg_check_modules(LIBXML2 REQUIRED IMPORTED_TARGET libxml-2.0)

find_program(GW_CONFIG gw-config REQUIRED
    DOC "Kannel gw-config, provides gwlib compiler and linker flags")

# Some gw-config scripts (e.g. Debian's) exit 1 even on success, so check the output instead
execute_process(COMMAND ${GW_CONFIG} --cflags
    OUTPUT_VARIABLE GW_CFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${GW_CONFIG} --libs
    OUTPUT_VARIABLE GW_LIBS OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT GW_CFLAGS OR NOT GW_LIBS)
    message(FATAL_ERROR "${GW_CONFIG} returned no --cflags or --libs output")
endif()
separate_arguments(GW_CFLAGS UNIX_COMMAND "${GW_CFLAGS}")
separate_arguments(GW_LIBS UNIX_COMMAND "${GW_LIBS}")

add_library(kannel::gwlib INTERFACE IMPORTED)
target_compile_options(kannel::gwlib INTERFACE ${GW_CFLAGS})
target_link_libraries(kannel::gwlib INTERFACE ${GW_LIBS})

# Kannel trunk renamed gwlib/regex.h (1.4.5) to gwlib/gw-regex.h
set(HAVE_GWLIB_GW_REGEX_H OFF)
foreach(flag IN LISTS GW_CFLAGS)
    if(flag MATCHES "^-I(.+)$" AND EXISTS "${CMAKE_MATCH_1}/gwlib/gw-regex.h")
        set(HAVE_GWLIB_GW_REGEX_H ON)
    endif()
endforeach()
if(HAVE_GWLIB_GW_REGEX_H)
    target_compile_definitions(kannel::gwlib INTERFACE HAVE_GWLIB_GW_REGEX_H=1)
endif()
message(STATUS "gwlib regex header: ${HAVE_GWLIB_GW_REGEX_H} (ON = gw-regex.h, OFF = regex.h)")

# --- Version and platform info (replaces autotools config.h) -----------------

set(KSMPPD_GIT_VERSION "" CACHE STRING
    "Version string reported at startup; detected with git describe when empty")
if(NOT KSMPPD_GIT_VERSION)
    find_package(Git QUIET)
    if(GIT_FOUND)
        execute_process(COMMAND ${GIT_EXECUTABLE} describe --always --tags
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            OUTPUT_VARIABLE KSMPPD_GIT_VERSION
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
    endif()
    if(NOT KSMPPD_GIT_VERSION)
        set(KSMPPD_GIT_VERSION "${PROJECT_VERSION}")
    endif()
endif()

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_VERSION}" KSMPPD_PLATFORM_INFO)

configure_file(cmake/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h @ONLY)

# --- Targets ----------------------------------------------------------------

add_library(smpp STATIC
    smpp/libsmpp/smpp_bearerbox.c
    smpp/libsmpp/smpp_database.c
    smpp/libsmpp/smpp_database_mysql.c
    smpp/libsmpp/smpp_esme.c
    smpp/libsmpp/smpp_http_client.c
    smpp/libsmpp/smpp_http_server.c
    smpp/libsmpp/smpp_listener.c
    smpp/libsmpp/smpp_pdu_util.c
    smpp/libsmpp/smpp_plugin.c
    smpp/libsmpp/smpp_queued_pdu.c
    smpp/libsmpp/smpp_queues.c
    smpp/libsmpp/smpp_route.c
    smpp/libsmpp/smpp_server.c
    smpp/libsmpp/smpp_server_cfg.c
    smpp/libsmpp/smpp_uuid.c)
set_target_properties(smpp PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(smpp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/smpp/libsmpp)
target_link_libraries(smpp PUBLIC
    kannel::gwlib
    PkgConfig::LIBEVENT
    PkgConfig::LIBXML2
    Threads::Threads
    ${CMAKE_DL_LIBS})

add_executable(ksmppd smpp/ksmppd.c)
target_include_directories(ksmppd PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(ksmppd PRIVATE smpp)

# --- Install ----------------------------------------------------------------

install(TARGETS ksmppd RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES ksmppd.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/ksmppd)
install(DIRECTORY example-configurations database-schemas
    DESTINATION ${CMAKE_INSTALL_DATADIR}/ksmppd)
