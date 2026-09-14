#!/usr/bin/env bash
# Native Windows build (GitHub Actions windows-latest or local Git Bash).
# Same output layout as Docker/Wine build: release tarball + native overlay (lite).
set -euo pipefail

HADOOP_VERSION="${1:-3.4.1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.conf"
HADOOP_SRC="${REPO_ROOT}/hadoop-src"
HADOOP_HOME="${REPO_ROOT}/hadoop-${HADOOP_VERSION}"
VCPKG_ROOT="${VCPKG_ROOT:-${REPO_ROOT}/.cache/vcpkg}"
VCPKG_COMMIT="${VCPKG_COMMIT:-7ffa425e1db8b0c3edf9c50f2f3a0f25a324541d}"
CACHE_DIR="${REPO_ROOT}/.cache/hadoop-releases"

resolve_git_ref() {
  local ver="$1" line key val
  if [[ -f "${VERSIONS_FILE}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// /}" ]] && continue
      key="${line%%=*}"
      val="${line#*=}"
      [[ "${key}" == "${ver}" ]] && { echo "${val}"; return 0; }
    done < "${VERSIONS_FILE}"
  fi
  echo "rel/release-${ver}"
}

HADOOP_GIT_REF="$(resolve_git_ref "${HADOOP_VERSION}")"

hadoop_src_version() {
  grep -m1 '<version>' "${HADOOP_SRC}/pom.xml" | sed 's|.*<version>\([^<]*\)</version>.*|\1|' | tr -d '[:space:]'
}

clone_hadoop() {
  local ref_file="${HADOOP_SRC}/.winutils-ref" cached_ref="" src_ver=""
  [[ -f "${ref_file}" ]] && cached_ref="$(cat "${ref_file}")"
  [[ -f "${HADOOP_SRC}/pom.xml" ]] && src_ver="$(hadoop_src_version)"

  if [[ -f "${HADOOP_SRC}/pom.xml" && "${cached_ref}" == "${HADOOP_GIT_REF}" && "${src_ver}" == "${HADOOP_VERSION}" ]]; then
    echo "[win] Hadoop sources already at ${HADOOP_GIT_REF} (${HADOOP_VERSION})"
  else
    echo "[win] Cloning Hadoop ${HADOOP_GIT_REF}"
    rm -rf "${HADOOP_SRC}"
    git clone --depth 1 --branch "${HADOOP_GIT_REF}" \
      https://github.com/apache/hadoop.git "${HADOOP_SRC}"
    echo "${HADOOP_GIT_REF}" > "${ref_file}"
  fi

  src_ver="$(hadoop_src_version)"
  [[ "${src_ver}" == "${HADOOP_VERSION}" ]] || {
    echo "[win] Error: source version ${src_ver} != ${HADOOP_VERSION}" >&2
    exit 1
  }
  git -C "${HADOOP_SRC}" config core.longpaths true
}

setup_vcpkg() {
  if [[ ! -d "${VCPKG_ROOT}/.git" ]]; then
    echo "[win] Cloning vcpkg ${VCPKG_COMMIT}"
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
    git -C "${VCPKG_ROOT}" checkout "${VCPKG_COMMIT}"
    cmd //c "${VCPKG_ROOT}\\bootstrap-vcpkg.bat" -disableMetrics
  fi

  local marker="${VCPKG_ROOT}/installed/x64-windows/include/boost/version.hpp"
  if [[ ! -f "${marker}" ]]; then
    echo "[win] Installing vcpkg packages (first run, may take a while)..."
    "${VCPKG_ROOT}/vcpkg.exe" install \
      boost:x64-windows protobuf:x64-windows openssl:x64-windows zlib:x64-windows
  fi
}

run_maven_native() {
  local vcpkg_prefix toolchain
  vcpkg_prefix="${VCPKG_ROOT}/installed/x64-windows"
  toolchain="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"

  export MAVEN_OPTS="${MAVEN_OPTS:--Xmx2048M -Xss128M}"

  cd "${HADOOP_SRC}"

  echo "[win] Maven: hadoop-common + hdfs-native-client (native-win)"
  mvn --batch-mode clean package \
    -pl hadoop-common-project/hadoop-common,hadoop-hdfs-project/hadoop-hdfs-native-client \
    -am \
    -Pnative-win \
    -Dhttps.protocols=TLSv1.2 \
    -DskipTests \
    -DskipDocs \
    -Dshell-executable="${SHELL_EXECUTABLE:-bash.exe}" \
    -Drequire.openssl \
    -Dopenssl.prefix="${vcpkg_prefix}" \
    -Dcmake.prefix.path="${vcpkg_prefix}" \
    -Dwindows.cmake.toolchain.file="${toolchain}" \
    -Dwindows.cmake.build.type=RelWithDebInfo \
    -Dwindows.build.hdfspp.dll=off \
    -Dwindows.no.sasl=on \
    -Duse.platformToolsetVersion=v143
}

write_build_meta() {
  local jdk_ver
  jdk_ver="$(java -version 2>&1 | head -1)"
  cat > "${HADOOP_HOME}/.winutils-build-meta" <<EOF
hadoop_version=${HADOOP_VERSION}
hadoop_git_ref=${HADOOP_GIT_REF}
build_method=windows-native
jdk_runtime=${jdk_ver}
runtime_note=Use the same Temurin JDK as this build (see Actions log / java -version)
EOF
}

[[ -n "${JAVA_HOME:-}" ]] || {
  echo "[win] Error: JAVA_HOME must point to Temurin 17 x64" >&2
  exit 1
}

echo "[win] Native Windows build Hadoop ${HADOOP_VERSION} ref=${HADOOP_GIT_REF}"
echo "[win] JAVA_HOME=${JAVA_HOME}"
java -version

clone_hadoop
setup_vcpkg
run_maven_native

COMMON_BIN="${HADOOP_SRC}/hadoop-common-project/hadoop-common/target/bin"
HDFS_BIN="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/target/bin"

[[ -f "${COMMON_BIN}/winutils.exe" && -f "${COMMON_BIN}/hadoop.dll" ]] || {
  echo "[win] Error: hadoop-common native build failed" >&2
  exit 1
}
[[ -f "${HDFS_BIN}/hdfs.dll" ]] || {
  echo "[win] Error: hdfs.dll missing (hdfs-native-client build failed)" >&2
  exit 1
}

export HADOOP_DIST_PROFILE="${HADOOP_DIST_PROFILE:-lite}"
bash "${REPO_ROOT}/docker/assemble-from-release.sh" \
  "${HADOOP_VERSION}" \
  "${HADOOP_HOME}" \
  "${COMMON_BIN}" \
  "${HDFS_BIN}" \
  "${CACHE_DIR}"

write_build_meta
echo "[win] Done: ${HADOOP_HOME}/"
