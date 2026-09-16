#!/usr/bin/env bash
# Build hdfs.dll on native Windows (CMake + Ninja + MSVC).
set -euo pipefail

export MSYS2_PATH_TYPE="${MSYS2_PATH_TYPE:-inherit}"

HADOOP_SRC="${HADOOP_SRC:-/h/hadoop-src}"
HDFS_MODULE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client"
BUILD_DIR="${HDFS_MODULE}/target/hdfs-native-build"
OUT_BIN="${HDFS_MODULE}/target/bin"
JAVAH_DIR="${BUILD_DIR}/javah"
VCPKG_ROOT="${VCPKG_ROOT:-/h/vcpkg}"

win_path() {
  if command -v cygpath &>/dev/null; then
    cygpath -m "$1"
  else
    echo "$1" | sed 's|^/\([a-zA-Z]\)/|\1:/|'
  fi
}

require_tool() {
  command -v "$1" &>/dev/null || {
    echo "[hdfs-native] Error: $1 not in PATH (load MSVC env first)" >&2
    exit 1
  }
}

ensure_ninja() {
  command -v ninja &>/dev/null && return 0
  local p
  for p in /c/Program\ Files/Microsoft\ Visual\ Studio/2022/*/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe \
           /c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/*/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe; do
    if [[ -f "$p" ]]; then
      export PATH="$(dirname "$p"):${PATH}"
      echo "[hdfs-native] ninja: $p"
      return 0
    fi
  done
  return 1
}

require_tool cmake
CMAKE_GENERATOR=( -G Ninja )
if ! ensure_ninja; then
  echo "[hdfs-native] ninja not found — fallback Visual Studio 2022 generator"
  CMAKE_GENERATOR=( -G "Visual Studio 17 2022" -A x64 )
fi

vcpkg_prefix="${VCPKG_ROOT}/installed/x64-windows"
toolchain="$(win_path "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")"
vcpkg_cmake_prefix="$(win_path "${vcpkg_prefix}")"
javah_win="$(win_path "${JAVAH_DIR}")"

mkdir -p "${JAVAH_DIR}" "${OUT_BIN}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "[hdfs-native] CMake configure (Ninja + vcpkg)..."
cmake -S "${HDFS_MODULE}/src" -B "${BUILD_DIR}" \
  "${CMAKE_GENERATOR[@]}" \
  -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
  -DCMAKE_PREFIX_PATH="${vcpkg_cmake_prefix}" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DGENERATED_JAVAH="${javah_win}" \
  -DJVM_ARCH_DATA_MODEL=64 \
  -DHADOOP_BUILD=1 \
  -DREQUIRE_OPENSSL=OFF \
  -DCUSTOM_OPENSSL_PREFIX="${vcpkg_cmake_prefix}" \
  -DBUILD_SHARED_HDFSPP=OFF \
  -DNO_SASL=ON

echo "[hdfs-native] Build target hdfs..."
cmake --build "${BUILD_DIR}" --config RelWithDebInfo --target hdfs --parallel -v

found=""
for dir in "${BUILD_DIR}/bin" "${BUILD_DIR}/bin/RelWithDebInfo"; do
  if [[ -f "${dir}/hdfs.dll" ]]; then
    found="${dir}"
    break
  fi
done

if [[ -z "${found}" ]]; then
  echo "[hdfs-native] Error: hdfs.dll missing after build" >&2
  find "${BUILD_DIR}" -name "hdfs.dll" 2>/dev/null | head -10 >&2 || true
  exit 1
fi

for artifact in hdfs.dll hdfs.lib hdfs.exp hdfs.pdb; do
  [[ -f "${found}/${artifact}" ]] && cp -f "${found}/${artifact}" "${OUT_BIN}/"
done

echo "[hdfs-native] OK: ${OUT_BIN}/hdfs.dll"
