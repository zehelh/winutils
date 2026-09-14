#!/usr/bin/env bash
set -euo pipefail

HADOOP_VERSION="${HADOOP_VERSION:?HADOOP_VERSION required}"
HADOOP_GIT_REF="${HADOOP_GIT_REF:?HADOOP_GIT_REF required}"

REPO_ROOT="/src"
HADOOP_SRC="${REPO_ROOT}/hadoop-src"
HADOOP_HOME="${REPO_ROOT}/hadoop-${HADOOP_VERSION}"
DEST="${HADOOP_HOME}/bin"
VCPKG_ROOT="/opt/vcpkg"
MAVEN_REPO="${MAVEN_REPO:-/root/.m2/repository}"

# Host-mounted volume: git rejects repos owned by a different user (container only).
git config --global --add safe.directory '*' 2>/dev/null || true

export WINEDEBUG=-all
export _MSPDBSRV_ENDPOINT_=winutils_build
WINE=$(command -v wine64 || command -v wine)

# shellcheck source=/dev/null
source /opt/msvc/bin/x64/msvcenv.sh
export PATH="/usr/local/bin:/opt/msvc/bin/x64:${PATH}"

"${WINE}" wineboot -i >/dev/null 2>&1 || true

# Persistent Wine desktop: avoids MSBuild/mspdbsrv pipe deadlocks on inherited handles.
nohup env WINEDEBUG=-all "${WINE}" explorer /desktop=winutils_build,800x600 \
  >/dev/null 2>&1 </dev/null &
desktop_pid=$!
sleep 2
if [[ -n "${BINDIR:-}" && -f "${BINDIR}/mspdbsrv.exe" ]]; then
  nohup env WINEDEBUG=-all _MSPDBSRV_ENDPOINT_="${_MSPDBSRV_ENDPOINT_}" \
    "${WINE}" "${BINDIR}/mspdbsrv.exe" -shutdowntime 86400 \
    >/dev/null 2>&1 </dev/null &
  sleep 1
fi
trap 'kill "${desktop_pid}" 2>/dev/null || true' EXIT

patch_hadoop_for_wine() {
  local ws="$1"
  local win="${ws}/hadoop-common-project/hadoop-common/src/main/winutils"
  local cfg="${win}/config.cpp"
  local hdr="${win}/include/winutils.h"

  # Windows SDK 10.0.26100+ exposes GetFileInformationByName in winbase.h.
  if [[ -f "${hdr}" ]] && grep -q 'DWORD GetFileInformationByName' "${hdr}"; then
    local f
    for f in "${hdr}" "${win}/libwinutils.c" "${win}/ls.c" "${win}/hardlink.c" "${win}/chmod.c"; do
      [[ -f "$f" ]] && sed -i 's/GetFileInformationByName/Hadoop_Winutils_GetFileInformationByName/g' "$f"
    done
  fi

  # Recent MSVC: "final" is a C++11 keyword, conflicts with #import msxml6.
  if [[ -f "${cfg}" ]] && ! grep -q 'rename("final"' "${cfg}"; then
    sed -i 's|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME")|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME") rename("final", "schemaFinal")|' "${cfg}"
  fi
}

hadoop_src_version() {
  grep -m1 '<version>' "${HADOOP_SRC}/pom.xml" | sed 's|.*<version>\([^<]*\)</version>.*|\1|' | tr -d '[:space:]'
}

clone_hadoop() {
  local ref_file="${HADOOP_SRC}/.winutils-ref"
  local cached_ref="" src_ver=""
  [[ -f "${ref_file}" ]] && cached_ref="$(cat "${ref_file}")"
  [[ -f "${HADOOP_SRC}/pom.xml" ]] && src_ver="$(hadoop_src_version)"

  # Re-clone if git ref OR pom version diverges (e.g. hadoop-src 3.4.3 + build 3.4.1).
  if [[ -f "${HADOOP_SRC}/pom.xml" && "${cached_ref}" == "${HADOOP_GIT_REF}" && "${src_ver}" == "${HADOOP_VERSION}" ]]; then
    echo "[build] Hadoop sources already at ${HADOOP_GIT_REF} (${HADOOP_VERSION})"
  else
    if [[ -n "${src_ver}" && "${src_ver}" != "${HADOOP_VERSION}" ]]; then
      echo "[build] Re-cloning: sources ${src_ver} != build ${HADOOP_VERSION}" >&2
    fi
    echo "[build] Cloning Hadoop ${HADOOP_GIT_REF} (target ${HADOOP_VERSION})"
    rm -rf "${HADOOP_SRC}"
    git clone --depth 1 --branch "${HADOOP_GIT_REF}" \
      https://github.com/apache/hadoop.git "${HADOOP_SRC}"
    echo "${HADOOP_GIT_REF}" > "${ref_file}"
    src_ver="$(hadoop_src_version)"
  fi

  if [[ "${src_ver}" != "${HADOOP_VERSION}" ]]; then
    echo "[build] Error: source version ${src_ver} != ${HADOOP_VERSION}" >&2
    exit 1
  fi

  git -C "${HADOOP_SRC}" config core.longpaths true
  patch_hadoop_for_wine "${HADOOP_SRC}"
  bash /docker/patch-hadoop-jni-wine.sh "${HADOOP_SRC}"
}

vcpkg_to_win() {
  "${WINE}" winepath -w "$1" 2>/dev/null | tr -d '\r'
}

maven_common_flags=(
  -Dhttps.protocols=TLSv1.2
  -DskipTests
  -DskipDocs
  -Denforcer.skip=true
  -Dshell-executable=/usr/bin/bash
)

run_maven() {
  local vcpkg_win toolchain_win
  vcpkg_win=$(vcpkg_to_win "${VCPKG_ROOT}")
  toolchain_win="${vcpkg_win}\\scripts\\buildsystems\\vcpkg.cmake"

  export MAVEN_OPTS="-Xmx2048M -Xss128M -Dmaven.repo.local=${MAVEN_REPO}"

  cd "${HADOOP_SRC}"

  echo "[build] Maven: hadoop-common (native-win only)"
  mvn clean package \
    -pl hadoop-common-project/hadoop-common -am \
    -Pnative-win \
    "${maven_common_flags[@]}" \
    -Drequire.openssl \
    -Dopenssl.prefix="${vcpkg_win}\\installed\\x64-windows" \
    -Dcmake.prefix.path="${vcpkg_win}\\installed\\x64-windows" \
    -Dwindows.cmake.toolchain.file="${toolchain_win}" \
    -Dwindows.cmake.build.type=RelWithDebInfo \
    -Dwindows.build.hdfspp.dll=off -Dwindows.no.sasl=on \
    -Duse.platformToolsetVersion=v145
}

HDFS_NATIVE_BIN="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/target/bin"

build_hdfs_native() {
  echo "[build] hdfs.dll (libhdfs via CMake/Ninja Wine)"
  HADOOP_VERSION="${HADOOP_VERSION}" bash /docker/build-hdfs-dll.sh
}

assemble_dist() {
  local hdfs_bin=""
  [[ -d "${HDFS_NATIVE_BIN}" && -f "${HDFS_NATIVE_BIN}/hdfs.dll" ]] && hdfs_bin="${HDFS_NATIVE_BIN}"
  bash /docker/assemble-from-release.sh \
    "${HADOOP_VERSION}" \
    "${HADOOP_HOME}" \
    "${HADOOP_SRC}/hadoop-common-project/hadoop-common/target/bin" \
    "${hdfs_bin}" \
    "/src/.cache/hadoop-releases"
}

write_build_meta() {
  cat > "${HADOOP_HOME}/.winutils-build-meta" <<EOF
hadoop_version=${HADOOP_VERSION}
hadoop_git_ref=${HADOOP_GIT_REF}
jdk_major=${JDK_MAJOR}
jdk_linux=${JAVA_HOME}
jdk_win_temurin=${TEMURIN_WIN_TAG}
runtime_note=Use Temurin ${JDK_MAJOR} x64 Windows (same major as jdk_win_temurin)
EOF
}

# shellcheck source=/dev/null
source /docker/jdk-env.sh

echo "[build] Hadoop ${HADOOP_VERSION} ref=${HADOOP_GIT_REF} JDK=${JDK_MAJOR}"
bash /docker/setup-jdk-win64.sh
bash /docker/patch-vcpkg.sh
/docker/install-vcpkg-deps.sh
clone_hadoop
HADOOP_SRC="${HADOOP_SRC}" HADOOP_VERSION="${HADOOP_VERSION}" bash /docker/verify-build-coherence.sh
run_maven
build_hdfs_native
assemble_dist
write_build_meta
HADOOP_SRC="${HADOOP_SRC}" HADOOP_VERSION="${HADOOP_VERSION}" bash /docker/verify-build-coherence.sh --with-native
echo "[build] Output: ${HADOOP_HOME}/"
ls -la "${DEST}/"

if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "${HOST_UID}:${HOST_GID}" "${HADOOP_HOME}" "${HADOOP_SRC}" 2>/dev/null || true
fi
