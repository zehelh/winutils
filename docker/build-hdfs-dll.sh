#!/usr/bin/env bash
# Compile hdfs.dll (libhdfs) via CMake/Ninja + MSVC Wine.
set -euo pipefail

HADOOP_SRC="${HADOOP_SRC:-/src/hadoop-src}"
HDFS_MODULE="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client"
BUILD_DIR="${HDFS_MODULE}/target/hdfs-wine-build"
OUT_BIN="${HDFS_MODULE}/target/bin"
JAVAH_DIR="${BUILD_DIR}/javah"
VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
JDK_WIN_ROOT="${JDK_WIN_ROOT:-/opt/jdk-win64}"

export WINEDEBUG=-all
WINE=$(command -v wine64 || command -v wine)
# shellcheck source=/dev/null
source /opt/msvc/bin/x64/msvcenv.sh
export PATH="/opt/msvc/bin/x64:/usr/local/bin:${PATH}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}"
export JAVA_WIN64_HOME="${JDK_WIN_ROOT}"
export HADOOP_WINE_CROSS_BUILD=1

bash /docker/setup-jdk-win32-headers.sh
bash /docker/setup-jdk-win64.sh
bash /docker/patch-vcpkg.sh
/docker/install-vcpkg-deps.sh
bash /docker/patch-hadoop-jni-wine.sh "${HADOOP_SRC}"

mkdir -p "${JAVAH_DIR}" "${OUT_BIN}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

vcpkg_prefix="${VCPKG_ROOT}/installed/x64-windows"

echo "[hdfs] CMake configure..."
cmake -S "${HDFS_MODULE}/src" -B "${BUILD_DIR}" \
  -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=/docker/toolchain-msvc-wine.cmake \
  -DCMAKE_PREFIX_PATH="${vcpkg_prefix}" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DGENERATED_JAVAH="${JAVAH_DIR}" \
  -DJVM_ARCH_DATA_MODEL=64 \
  -DHADOOP_BUILD=1 \
  -DREQUIRE_OPENSSL=OFF \
  -DCUSTOM_OPENSSL_PREFIX="${vcpkg_prefix}" \
  -DBUILD_SHARED_HDFSPP=OFF \
  -DNO_SASL=ON

echo "[hdfs] Ninja: cible hdfs..."
ninja -C "${BUILD_DIR}" hdfs

for artifact in hdfs.dll hdfs.lib hdfs.exp hdfs.pdb; do
  [[ -f "${BUILD_DIR}/bin/${artifact}" ]] && cp -f "${BUILD_DIR}/bin/${artifact}" "${OUT_BIN}/"
done

[[ -f "${OUT_BIN}/hdfs.dll" ]] || {
  echo "[hdfs] Erreur: hdfs.dll absent apres build" >&2
  exit 1
}
echo "[hdfs] OK: ${OUT_BIN}/hdfs.dll"
