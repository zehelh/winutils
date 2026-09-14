#!/usr/bin/env bash
# Native Windows build (GitHub Actions windows-latest or local Git Bash).
# Same output layout as Docker/Wine build: release tarball + native overlay (lite).
set -euo pipefail

# Git for Windows: preserve Windows PATH (MSBuild, cl.exe) inside bash.
export MSYS2_PATH_TYPE="${MSYS2_PATH_TYPE:-inherit}"

HADOOP_VERSION="${1:-3.4.1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.conf"
# Short path on Windows (Hadoop BUILDING.txt — avoid MAX_PATH).
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  HADOOP_SRC="${HADOOP_SRC:-/c/hadoop-src}"
elif [[ "${OS:-}" == "Windows_NT" ]]; then
  HADOOP_SRC="${HADOOP_SRC:-/c/hadoop-src}"
else
  HADOOP_SRC="${HADOOP_SRC:-${REPO_ROOT}/hadoop-src}"
fi
HADOOP_HOME="${REPO_ROOT}/hadoop-${HADOOP_VERSION}"
REF_FILE="${REPO_ROOT}/.hadoop-src-ref"
VCPKG_ROOT="${VCPKG_ROOT:-${REPO_ROOT}/.cache/vcpkg}"
# Native Windows: recent vcpkg (VS 2022). Docker/Wine keeps 7ffa425 in docker/Dockerfile.
# MSYS2 packages expire on mirrors; use a recent vcpkg tag (see https://github.com/microsoft/vcpkg/releases).
VCPKG_COMMIT="${VCPKG_COMMIT:-2026.06.24}"
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

configure_git_longpaths() {
  git config --global core.longpaths true
}

clone_hadoop() {
  local cached_ref="" src_ver=""
  configure_git_longpaths
  [[ -f "${REF_FILE}" ]] && cached_ref="$(cat "${REF_FILE}")"
  [[ -f "${HADOOP_SRC}/pom.xml" ]] && src_ver="$(hadoop_src_version)"

  if [[ -f "${HADOOP_SRC}/pom.xml" && "${cached_ref}" == "${HADOOP_GIT_REF}" && "${src_ver}" == "${HADOOP_VERSION}" ]]; then
    echo "[win] Hadoop sources already at ${HADOOP_GIT_REF} (${HADOOP_VERSION})"
  else
    echo "[win] Cloning Hadoop ${HADOOP_GIT_REF} -> ${HADOOP_SRC}"
    rm -rf "${HADOOP_SRC}"
    mkdir -p "$(dirname "${HADOOP_SRC}")"
    if ! git -c core.longpaths=true clone --depth 1 --branch "${HADOOP_GIT_REF}" \
      https://github.com/apache/hadoop.git "${HADOOP_SRC}"; then
      echo "[win] Error: git clone/checkout failed (Windows MAX_PATH? use /c/hadoop-src + core.longpaths)" >&2
      exit 1
    fi
    echo "${HADOOP_GIT_REF}" > "${REF_FILE}"
  fi

  git -C "${HADOOP_SRC}" config core.longpaths true

  src_ver="$(hadoop_src_version)"
  [[ "${src_ver}" == "${HADOOP_VERSION}" ]] || {
    echo "[win] Error: source version ${src_ver} != ${HADOOP_VERSION}" >&2
    exit 1
  }
}

ensure_vcpkg_repo() {
  local ref_file="${VCPKG_ROOT}/.vcpkg-ref"
  local cached_ref=""

  [[ -f "${ref_file}" ]] && cached_ref="$(cat "${ref_file}")"

  if [[ -d "${VCPKG_ROOT}/.git" && "${cached_ref}" == "${VCPKG_COMMIT}" ]]; then
    echo "[win] vcpkg already at ${VCPKG_COMMIT}"
    return 0
  fi

  if [[ -d "${VCPKG_ROOT}/.git" ]]; then
    echo "[win] vcpkg: switching ${cached_ref:-unknown} -> ${VCPKG_COMMIT}"
    rm -rf "${VCPKG_ROOT}"
  fi

  echo "[win] Cloning vcpkg ${VCPKG_COMMIT}"
  if ! git clone --depth 1 --branch "${VCPKG_COMMIT}" \
    https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}" 2>/dev/null; then
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
    git -C "${VCPKG_ROOT}" checkout "${VCPKG_COMMIT}"
  fi
  echo "${VCPKG_COMMIT}" > "${ref_file}"
}

bootstrap_vcpkg() {
  if [[ -f "${VCPKG_ROOT}/vcpkg.exe" ]]; then
    return 0
  fi
  echo "[win] Bootstrapping vcpkg (VS 2022 / MSVC required)"
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "${REPO_ROOT}/scripts/bootstrap-vcpkg.ps1" \
    -VcpkgRoot "${VCPKG_ROOT}"
}

setup_vcpkg() {
  ensure_vcpkg_repo
  bootstrap_vcpkg

  local marker="${VCPKG_ROOT}/installed/x64-windows/include/boost/version.hpp"
  if [[ ! -f "${marker}" ]]; then
    echo "[win] Installing vcpkg packages (first run, may take a while)..."
    "${VCPKG_ROOT}/vcpkg.exe" install \
      boost:x64-windows protobuf:x64-windows openssl:x64-windows zlib:x64-windows
  fi
}

require_msbuild() {
  if command -v msbuild.exe &>/dev/null || command -v MSBuild.exe &>/dev/null; then
    return 0
  fi
  echo "[win] Error: msbuild not in PATH (Visual Studio C++ Build Tools required)" >&2
  echo "[win] On self-hosted runners, run: pwsh scripts/setup-windows-runner.ps1" >&2
  exit 1
}

run_maven_native() {
  local vcpkg_prefix toolchain
  vcpkg_prefix="${VCPKG_ROOT}/installed/x64-windows"
  toolchain="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"

  require_msbuild
  export MAVEN_OPTS="${MAVEN_OPTS:--Xmx4096M -Xss128M}"

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
echo "[win] HADOOP_SRC=${HADOOP_SRC}"
echo "[win] JAVA_HOME=${JAVA_HOME}"
java -version

clone_hadoop
bash "${REPO_ROOT}/scripts/patch-hadoop-winutils-sdk.sh" "${HADOOP_SRC}"
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
