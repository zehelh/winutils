#!/usr/bin/env bash
# Lite HDFS native build for winutils: hdfs.dll only (no libhdfspp tests, no libhdfs tests).
# Mirrors docker/patch-hadoop-jni-wine.sh HDFS parts, without Wine-specific JNI.
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
if [[ -f "${HDFS_POM}" ]] && grep -q 'ALL_BUILD.vcxproj' "${HDFS_POM}" && ! grep -q 'HADOOP_WINUTILS_LITE_MSBuild' "${HDFS_POM}"; then
  echo "[patch-hdfs] pom: msbuild hdfs.vcxproj /t:hdfs instead of ALL_BUILD"
  sed -i 's|ALL_BUILD\.vcxproj /nologo|hdfs.vcxproj /t:hdfs /nologo|' "${HDFS_POM}"
  # Marker comment (harmless inside XML if we add as property - use file sentinel instead)
  touch "${HDFS_MODULE}/.${MARKER}_msbuild"
fi

if [[ -f "${HDFS_CMAKE}" ]] && ! grep -q "${MARKER}" "${HDFS_CMAKE}"; then
  echo "[patch-hdfs] CMakeLists: x-platform + libhdfs only"
  python3 - "${HDFS_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
marker = "HADOOP_WINUTILS_LITE"
text = open(path).read()
old = "add_subdirectory(main/native/libhdfs)\nadd_subdirectory(main/native/libhdfs-tests)\nadd_subdirectory(main/native/libhdfs-examples)"
new = f"""# {marker}
add_subdirectory(main/native/libhdfspp/lib/x-platform)
add_subdirectory(main/native/libhdfs)
# {marker}: skip libhdfs-tests/examples and full libhdfspp"""
if old not in text:
    raise SystemExit(f"patch hdfs cmake: target block not found in {path}")
text = text.replace(old, new, 1)
# Drop full libhdfspp (tests, gmock, boost link); x-platform is added above.
import re
libhdfspp_block = re.compile(
    r"# Temporary fix to disable Libhdfs\+\+.*?"
    r"endif \(THREAD_LOCAL_SUPPORTED\)\n",
    re.S,
)
if not libhdfspp_block.search(text):
    raise SystemExit(f"patch hdfs cmake: libhdfspp block not found in {path}")
text = libhdfspp_block.sub(
    f"# {marker}: full libhdfspp skipped (x-platform built above)\n",
    text,
    count=1,
)
open(path, "w").write(text)
PY
fi

if [[ -f "${LIBHDFS_CMAKE}" ]] && ! grep -q "${MARKER}" "${LIBHDFS_CMAKE}"; then
  echo "[patch-hdfs] libhdfs: skip Windows libhdfs unit tests"
  python3 - "${LIBHDFS_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
marker = "HADOOP_WINUTILS_LITE"
text = open(path).read()
if marker in text:
    raise SystemExit(0)
start = text.find("build_libhdfs_test(test_libhdfs_ops")
end = text.find("if (NOT WIN32 AND NOT APPLE)")
if start < 0 or end < 0 or end <= start:
    raise SystemExit(f"patch libhdfs: test block not found in {path}")
wrapped = f"if (NOT WIN32)\n{text[start:end]}endif (NOT WIN32)\n\n"
text = text[:start] + wrapped + text[end:]
open(path, "w").write(text)
PY
fi

if [[ -f "${XPLATFORM_CMAKE}" ]] && ! grep -q 'HADOOP_WINUTILS_XPLATFORM_INCLUDES' "${XPLATFORM_CMAKE}"; then
  echo "[patch-hdfs] x-platform: parent lib include path"
  python3 - "${XPLATFORM_CMAKE}" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
insert = """
# HADOOP_WINUTILS_XPLATFORM_INCLUDES
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

echo "[patch-hdfs] lite HDFS native patches OK"
