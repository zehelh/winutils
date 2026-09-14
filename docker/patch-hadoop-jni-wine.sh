#!/usr/bin/env bash
set -euo pipefail

HADOOP_SRC="${1:?HADOOP_SRC required}"
JNI_CMAKE="${HADOOP_SRC}/hadoop-common-project/hadoop-common/HadoopJNI.cmake"
HDFS_CMAKE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/src/CMakeLists.txt"
LIBHDFS_CMAKE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/src/main/native/libhdfs/CMakeLists.txt"

[[ -f "${JNI_CMAKE}" ]] || exit 0

if ! grep -q 'HADOOP_WINE_CROSS_BUILD' "${JNI_CMAKE}"; then
  python3 - "${JNI_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """#
# Otherwise, use the standard FindJNI module to locate the JNI components.
#
else()
    find_package(Java REQUIRED)
    include(UseJava)
    find_package(JNI REQUIRED)
endif()"""
new = """#
# Wine cross-build (Linux host + MSVC): OpenJDK Linux headers, Windows jvm.lib link.
#
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows" AND DEFINED ENV{HADOOP_WINE_CROSS_BUILD})
    file(TO_CMAKE_PATH "$ENV{JAVA_HOME}" _java_home)
    file(TO_CMAKE_PATH "$ENV{JAVA_WIN64_HOME}" _java_win)
    set(JAVA_INCLUDE_PATH "${_java_home}/include")
    set(JAVA_INCLUDE_PATH2 "${_java_home}/include/win32")
    set(JNI_INCLUDE_DIRS ${JAVA_INCLUDE_PATH} ${JAVA_INCLUDE_PATH2})
    find_library(JAVA_JVM_LIBRARY
        NAMES jvm.lib
        PATHS "${_java_win}/lib" "${_java_win}/jre/bin/server"
        NO_DEFAULT_PATH)
    set(JNI_LIBRARIES ${JAVA_JVM_LIBRARY})
    if(NOT JAVA_JVM_LIBRARY OR NOT EXISTS "${JAVA_INCLUDE_PATH}/jni.h")
        message(FATAL_ERROR "Wine JNI: invalid JAVA_HOME or JAVA_WIN64_HOME")
    endif()
    message("Wine JNI OK: ${JAVA_JVM_LIBRARY}")
#
# Otherwise, use the standard FindJNI module to locate the JNI components.
#
else()
    find_package(Java REQUIRED)
    include(UseJava)
    find_package(JNI REQUIRED)
endif()"""
if old not in text:
    raise SystemExit(f"patch JNI: target block not found in {path}")
open(path, "w").write(text.replace(old, new, 1))
PY
fi

if [[ -f "${HDFS_CMAKE}" ]] && ! grep -q 'libhdfspp/lib/x-platform' "${HDFS_CMAKE}"; then
  python3 - "${HDFS_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "add_subdirectory(main/native/libhdfs)\nadd_subdirectory(main/native/libhdfs-tests)\nadd_subdirectory(main/native/libhdfs-examples)"
new = """# Wine: x-platform required by libhdfs, without full libhdfspp.
if(DEFINED ENV{HADOOP_WINE_CROSS_BUILD})
    add_subdirectory(main/native/libhdfspp/lib/x-platform)
endif()
add_subdirectory(main/native/libhdfs)
if(NOT DEFINED ENV{HADOOP_WINE_CROSS_BUILD})
    add_subdirectory(main/native/libhdfs-tests)
    add_subdirectory(main/native/libhdfs-examples)
endif()"""
if old not in text:
    raise SystemExit(f"patch hdfs cmake: target block not found in {path}")
text = text.replace(old, new, 1)
if "if (THREAD_LOCAL_SUPPORTED AND NOT DEFINED ENV{HADOOP_WINE_CROSS_BUILD})" not in text:
    text = text.replace(
        "if (THREAD_LOCAL_SUPPORTED)",
        "if (THREAD_LOCAL_SUPPORTED AND NOT DEFINED ENV{HADOOP_WINE_CROSS_BUILD})",
        1,
    )
    text = text.replace(
        "endif (THREAD_LOCAL_SUPPORTED)",
        "endif (THREAD_LOCAL_SUPPORTED AND NOT DEFINED ENV{HADOOP_WINE_CROSS_BUILD})",
        1,
    )
open(path, "w").write(text)
PY
fi

if [[ -f "${LIBHDFS_CMAKE}" ]] && ! grep -q 'HADOOP_WINE_LIBHDFS_ONLY_SHARED' "${LIBHDFS_CMAKE}"; then
  python3 - "${LIBHDFS_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
marker = "HADOOP_WINE_LIBHDFS_ONLY_SHARED"
if marker in text:
    raise SystemExit(0)
src_block = """    exception.c
    jni_helper.c
    hdfs.c
    jclasses.c
    ${OS_DIR}/mutexes.c
    ${OS_DIR}/thread_local_storage.c
    $<TARGET_OBJECTS:x_platform_obj>
    $<TARGET_OBJECTS:x_platform_obj_c_api>
)"""
old = f"""hadoop_add_dual_library(hdfs
{src_block}
if(NEED_LINK_DL)
   set(LIB_DL dl)
endif()

hadoop_target_link_dual_libraries(hdfs
    ${{JAVA_JVM_LIBRARY}}
    ${{LIB_DL}}
    ${{OS_LINK_LIBRARIES}}
)

hadoop_dual_output_directory(hdfs ${{OUT_DIR}})"""
new = f"""# {marker}
if(DEFINED ENV{{HADOOP_WINE_CROSS_BUILD}})
    add_library(hdfs SHARED
{src_block}
    if(NEED_LINK_DL)
       set(LIB_DL dl)
    endif()
    target_link_libraries(hdfs
        ${{JAVA_JVM_LIBRARY}}
        ${{LIB_DL}}
        ${{OS_LINK_LIBRARIES}}
    )
    hadoop_output_directory(hdfs ${{OUT_DIR}})
else()
    hadoop_add_dual_library(hdfs
{src_block}
    if(NEED_LINK_DL)
       set(LIB_DL dl)
    endif()
    hadoop_target_link_dual_libraries(hdfs
        ${{JAVA_JVM_LIBRARY}}
        ${{LIB_DL}}
        ${{OS_LINK_LIBRARIES}}
    )
    hadoop_dual_output_directory(hdfs ${{OUT_DIR}})
endif()"""
if old not in text:
    raise SystemExit(f"patch libhdfs: target block not found in {path}")
text = text.replace(old, new, 1)
# Skip libhdfs tests in Wine cross-build
text = text.replace(
    "build_libhdfs_test(test_libhdfs_ops hdfs_static test_libhdfs_ops.c)",
    "if(NOT DEFINED ENV{HADOOP_WINE_CROSS_BUILD})\nbuild_libhdfs_test(test_libhdfs_ops hdfs_static test_libhdfs_ops.c)",
    1,
)
text = text.replace(
    "add_libhdfs_test(test_libhdfs_threaded hdfs_static)\n\nif (NOT WIN32 AND NOT APPLE)",
    "add_libhdfs_test(test_libhdfs_threaded hdfs_static)\nendif()\n\nif (NOT WIN32 AND NOT APPLE)",
    1,
)
open(path, "w").write(text)
PY
fi

XPLATFORM_CMAKE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/src/main/native/libhdfspp/lib/x-platform/CMakeLists.txt"
if [[ -f "${XPLATFORM_CMAKE}" ]] && ! grep -q 'HADOOP_WINE_XPLATFORM_INCLUDES' "${XPLATFORM_CMAKE}"; then
  python3 - "${XPLATFORM_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
insert = """
# HADOOP_WINE_XPLATFORM_INCLUDES
set(_xplatform_lib_dir ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_include_directories(x_platform_obj PUBLIC ${_xplatform_lib_dir})
target_include_directories(x_platform_obj_c_api PUBLIC ${_xplatform_lib_dir})
"""
text = text.replace(
    'target_compile_definitions(x_platform_obj_c_api PRIVATE USE_X_PLATFORM_DIRENT)',
    'target_compile_definitions(x_platform_obj_c_api PRIVATE USE_X_PLATFORM_DIRENT)' + insert,
    1,
)
open(path, "w").write(text)
PY
fi
