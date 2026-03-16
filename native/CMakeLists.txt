cmake_minimum_required(VERSION 3.16)
project(zoom_worker CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Detect architecture for SDK path
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/zoom-meeting-sdk-arm64")
else()
    set(SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/zoom-meeting-sdk-x86_64")
endif()

message(STATUS "Using Zoom SDK from: ${SDK_DIR}")

# nlohmann/json (header-only)
include(FetchContent)
FetchContent_Declare(
    json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
)
FetchContent_MakeAvailable(json)

# Zoom SDK
set(SDK_INCLUDE_DIR "${SDK_DIR}/h")
set(SDK_LIB_DIR "${SDK_DIR}")

# GLib2 bundled with SDK
set(GLIB_DIR "${SDK_DIR}/libglib2")
set(GLIB_INCLUDE_DIRS
    "${GLIB_DIR}/include/glib-2.0"
    "${GLIB_DIR}/lib/glib-2.0/include"
)
set(GLIB_LIB_DIR "${GLIB_DIR}/lib")

add_executable(zoom_worker zoom_worker.cpp)

target_include_directories(zoom_worker PRIVATE
    ${SDK_INCLUDE_DIR}
    ${GLIB_INCLUDE_DIRS}
)

target_link_directories(zoom_worker PRIVATE
    ${SDK_LIB_DIR}
    ${GLIB_LIB_DIR}
)

target_link_libraries(zoom_worker PRIVATE
    meetingsdk
    glib-2.0
    nlohmann_json::nlohmann_json
    pthread
)

# Set RPATH so the binary finds SDK .so files at runtime
set_target_properties(zoom_worker PROPERTIES
    INSTALL_RPATH "${SDK_LIB_DIR};${GLIB_LIB_DIR}"
    BUILD_RPATH "${SDK_LIB_DIR};${GLIB_LIB_DIR}"
)
