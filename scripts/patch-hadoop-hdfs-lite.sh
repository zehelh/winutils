#!/usr/bin/env bash
# Lite HDFS native build for winutils: hdfs.dll only (no libhdfspp tests, no libhdfs tests).
# Pure bash/awk/sed — no python3 (Windows self-hosted runners often lack it).
set -euo pipefail

HADOOP_SRC="${1:?HADOOP_SRC required}"
HDFS_MODULE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client"
HDFS_CMAKE="${HDFS_MODULE}/src/CMakeLists.txt"
LIBHDFS_CMAKE="${HDFS_MODULE}/src/main/native/libhdfs/CMakeLists.txt"
XPLATFORM_CMAKE="${HDFS_MODULE}/src/main/native/libhdfspp/lib/x-platform/CMakeLists.txt"
HDFS_POM="${HDFS_MODULE}/pom.xml"
MARKER="HADOOP_WINUTILS_LITE"

if [[ ! -d "${HDFS_MODULE}" ]]; then
  echo "[patch-hdfs] skip: ${HDFS_MODULE} not found"
  exit 0
fi

# MSBuild: ALL_BUILD pulls libhdfs-tests + libhdfspp tests (native_mini_dfs, gmock, etc.).
if [[ -f "${HDFS_POM}" ]] && grep -q 'ALL_BUILD.vcxproj' "${HDFS_POM}"; then
  echo "[patch-hdfs] pom: msbuild hdfs.vcxproj /t:hdfs instead of ALL_BUILD"
  sed -i 's|ALL_BUILD\.vcxproj /nologo|hdfs.vcxproj /t:hdfs /nologo|' "${HDFS_POM}"
fi

if [[ -f "${HDFS_CMAKE}" ]] && ! grep -q "${MARKER}" "${HDFS_CMAKE}"; then
  echo "[patch-hdfs] CMakeLists: x-platform + libhdfs only"
  awk -v marker="${MARKER}" '
    /add_subdirectory\(main\/native\/libhdfs\)/ && !done {
      print "# " marker
      print "add_subdirectory(main/native/libhdfspp/lib/x-platform)"
      print "add_subdirectory(main/native/libhdfs)"
      print "# " marker ": skip libhdfs-tests/examples and full libhdfspp"
      done = 1
      next
    }
    /add_subdirectory\(main\/native\/libhdfs-tests\)/ { next }
    /add_subdirectory\(main\/native\/libhdfs-examples\)/ { next }
    /# Temporary fix to disable Libhdfs/ {
      print "# " marker ": full libhdfspp skipped (x-platform built above)"
      skip = 1
      next
    }
    skip && /endif \(THREAD_LOCAL_SUPPORTED\)/ { skip = 0; next }
    skip { next }
    { print }
  ' "${HDFS_CMAKE}" > "${HDFS_CMAKE}.tmp"
  mv "${HDFS_CMAKE}.tmp" "${HDFS_CMAKE}"
  grep -q "${MARKER}" "${HDFS_CMAKE}" || {
    echo "[patch-hdfs] Error: CMakeLists patch failed (${HDFS_CMAKE})" >&2
    exit 1
  }
fi

if [[ -f "${LIBHDFS_CMAKE}" ]] && ! grep -q "${MARKER}" "${LIBHDFS_CMAKE}"; then
  echo "[patch-hdfs] libhdfs: skip Windows libhdfs unit tests"
  awk -v marker="${MARKER}" '
    /build_libhdfs_test\(test_libhdfs_ops/ && !wrapped {
      print "# " marker
      print "if (NOT WIN32)"
      wrapped = 1
    }
    /if \(NOT WIN32 AND NOT APPLE\)/ && wrapped {
      print "endif (NOT WIN32)"
      print ""
      wrapped = 0
    }
    { print }
  ' "${LIBHDFS_CMAKE}" > "${LIBHDFS_CMAKE}.tmp"
  mv "${LIBHDFS_CMAKE}.tmp" "${LIBHDFS_CMAKE}"
fi

if [[ -f "${XPLATFORM_CMAKE}" ]] && ! grep -q 'HADOOP_WINUTILS_XPLATFORM_INCLUDES' "${XPLATFORM_CMAKE}"; then
  echo "[patch-hdfs] x-platform: parent lib include path"
  awk '
    /target_compile_definitions\(x_platform_obj_c_api PRIVATE USE_X_PLATFORM_DIRENT\)/ && !done {
      print
      print ""
      print "# HADOOP_WINUTILS_XPLATFORM_INCLUDES"
      print "set(_xplatform_lib_dir ${CMAKE_CURRENT_SOURCE_DIR}/..)"
      print "target_include_directories(x_platform_obj PUBLIC ${_xplatform_lib_dir})"
      print "target_include_directories(x_platform_obj_c_api PUBLIC ${_xplatform_lib_dir})"
      done = 1
      next
    }
    { print }
  ' "${XPLATFORM_CMAKE}" > "${XPLATFORM_CMAKE}.tmp"
  mv "${XPLATFORM_CMAKE}.tmp" "${XPLATFORM_CMAKE}"
fi

echo "[patch-hdfs] lite HDFS native patches OK"
