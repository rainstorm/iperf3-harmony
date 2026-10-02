# CMakeLists for libiperf_napi.so: the ESnet iperf 3.22 C sources
# (third_party/iperf, kept pristine) plus the NAPI bridge, one shared library.
cmake_minimum_required(VERSION 3.5.0)
project(iperf_napi)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

# Upstream tree: shallow clone of esnet/iperf master @ 49f21b4 (3.22).
set(IPERF3_SOURCE_DIR "${NATIVERENDER_ROOT_PATH}/../../../../third_party/iperf"
    CACHE PATH "iperf3 upstream source tree")
if(NOT EXISTS "${IPERF3_SOURCE_DIR}/src/iperf_api.h")
    message(FATAL_ERROR
        "iperf3 sources not found under ${IPERF3_SOURCE_DIR}; expected the "
        "esnet/iperf checkout at iperf3-harmony/third_party/iperf.")
endif()

# config/ holds the adapted iperf_config.h and the generated version.h; it
# must precede upstream src/ on the include path because the pristine tree
# has neither file.
include_directories(${NATIVERENDER_ROOT_PATH}/config)
include_directories(${IPERF3_SOURCE_DIR}/src)

# Mirrors libiperf_la_SOURCES from upstream src/Makefile.am -- all 18 .c
# files, listed explicitly (no GLOB). main.c (CLI entry) and the t_*.c test
# programs are excluded on purpose. No OpenSSL: HAVE_SSL stays undefined in
# config/iperf_config.h, and iperf_auth.c is entirely wrapped in
# #if defined(HAVE_SSL), so it compiles to an empty unit.
set(IPERF3_UPSTREAM_SOURCES
    ${IPERF3_SOURCE_DIR}/src/cjson.c
    ${IPERF3_SOURCE_DIR}/src/iperf_api.c
    ${IPERF3_SOURCE_DIR}/src/iperf_error.c
    ${IPERF3_SOURCE_DIR}/src/iperf_auth.c
    ${IPERF3_SOURCE_DIR}/src/iperf_client_api.c
    ${IPERF3_SOURCE_DIR}/src/iperf_locale.c
    ${IPERF3_SOURCE_DIR}/src/iperf_server_api.c
    ${IPERF3_SOURCE_DIR}/src/iperf_tcp.c
    ${IPERF3_SOURCE_DIR}/src/iperf_udp.c
    ${IPERF3_SOURCE_DIR}/src/iperf_sctp.c
    ${IPERF3_SOURCE_DIR}/src/iperf_util.c
    ${IPERF3_SOURCE_DIR}/src/iperf_time.c
    ${IPERF3_SOURCE_DIR}/src/iperf_pthread.c
    ${IPERF3_SOURCE_DIR}/src/dscp.c
    ${IPERF3_SOURCE_DIR}/src/net.c
    ${IPERF3_SOURCE_DIR}/src/tcp_info.c
    ${IPERF3_SOURCE_DIR}/src/timer.c
    ${IPERF3_SOURCE_DIR}/src/units.c
)

# Patches to upstream behaviour, each its own translation unit so that
# third_party/iperf stays pristine:
#   iperf_cancel.c       -- cross-thread cancellation for stop() (upstream
#                           has no public cancel API)
#   iperf_pthread_shim.c -- pthread_cancel()/pthread_setcancelstate()/
#                           pthread_setcanceltype(), missing from the OHOS
#                           musl libc (OpenHarmony issues I6B39G / I9B28B);
#                           same workaround upstream ships for Android in
#                           src/iperf_pthread.c
set(IPERF3_PATCH_SOURCES
    ${NATIVERENDER_ROOT_PATH}/patch/iperf_cancel.c
    ${NATIVERENDER_ROOT_PATH}/patch/iperf_pthread_shim.c
)

# Must be set before any target is created: CMAKE_<LANG>_STANDARD only
# initializes the target property at creation time, so an earlier target
# would silently keep the toolchain default. C11 with GNU extensions keeps
# `linux` predefined, which selects the real struct tcp_info branch in
# iperf.h, and keeps musl's default feature-test visibility (getline,
# daemon, sendfile, clock_nanosleep).
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(iperf_napi SHARED
    ${IPERF3_UPSTREAM_SOURCES}
    ${IPERF3_PATCH_SOURCES}
    ${NATIVERENDER_ROOT_PATH}/napi_init.cpp
    ${NATIVERENDER_ROOT_PATH}/iperf_bridge.cpp
)

# Pinned on the target as well so the dialect guarantee survives a future
# reordering of this file.
set_target_properties(iperf_napi PROPERTIES
    C_STANDARD 11
    C_EXTENSIONS ON
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# iperf.h defines _GNU_SOURCE itself if missing; the command-line definition
# also covers the TUs that include system headers before iperf.h (cjson.c,
# iperf_client_api.c).
target_compile_definitions(iperf_napi PRIVATE _GNU_SOURCE)

# libace_napi.z.so is the NAPI runtime. No -lm/-lpthread/-lrt: on musl,
# round() (the only libm symbol iperf references), pthread_* and
# clock_gettime all live in libc. If the linker ever reports an unresolved
# `round`, add `m` to the list below.
target_link_libraries(iperf_napi PUBLIC libace_napi.z.so)

# Upstream noinst test programs (src/Makefile.am): each is a standalone
# program with its own main(), so none may be compiled into the SHARED
# library (duplicate main()). Wired as EXCLUDE_FROM_ALL executables so the
# default DevEco build never touches them but they stay buildable on demand:
#   cmake --build <build-dir> --target iperf_t_timer
# t_auth.c links in this OpenSSL-free config (its test body sits inside
# #if defined(HAVE_SSL), stub main() otherwise). main.c (CLI binary -- an
# app process cannot run a CLI) and t_api.c (needs a live peer) are not
# referenced at all.
add_executable(iperf_t_timer EXCLUDE_FROM_ALL
    ${IPERF3_SOURCE_DIR}/src/t_timer.c)
target_include_directories(iperf_t_timer PRIVATE
    ${NATIVERENDER_ROOT_PATH}/config ${IPERF3_SOURCE_DIR}/src)
target_compile_definitions(iperf_t_timer PRIVATE _GNU_SOURCE)
target_link_libraries(iperf_t_timer PRIVATE iperf_napi)

add_executable(iperf_t_units EXCLUDE_FROM_ALL
    ${IPERF3_SOURCE_DIR}/src/t_units.c)
target_include_directories(iperf_t_units PRIVATE
    ${NATIVERENDER_ROOT_PATH}/config ${IPERF3_SOURCE_DIR}/src)
target_compile_definitions(iperf_t_units PRIVATE _GNU_SOURCE)
target_link_libraries(iperf_t_units PRIVATE iperf_napi)

add_executable(iperf_t_uuid EXCLUDE_FROM_ALL
    ${IPERF3_SOURCE_DIR}/src/t_uuid.c)
target_include_directories(iperf_t_uuid PRIVATE
    ${NATIVERENDER_ROOT_PATH}/config ${IPERF3_SOURCE_DIR}/src)
target_compile_definitions(iperf_t_uuid PRIVATE _GNU_SOURCE)
target_link_libraries(iperf_t_uuid PRIVATE iperf_napi)

add_executable(iperf_t_auth EXCLUDE_FROM_ALL
    ${IPERF3_SOURCE_DIR}/src/t_auth.c)
target_include_directories(iperf_t_auth PRIVATE
    ${NATIVERENDER_ROOT_PATH}/config ${IPERF3_SOURCE_DIR}/src)
target_compile_definitions(iperf_t_auth PRIVATE _GNU_SOURCE)
target_link_libraries(iperf_t_auth PRIVATE iperf_napi)
