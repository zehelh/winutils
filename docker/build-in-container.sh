#!/usr/bin/env bash
set -euo pipefail

HADOOP_VERSION="${HADOOP_VERSION:?HADOOP_VERSION requis}"
HADOOP_GIT_REF="${HADOOP_GIT_REF:?HADOOP_GIT_REF requis}"

REPO_ROOT="/src"
HADOOP_SRC="${REPO_ROOT}/hadoop-src"
HADOOP_HOME="${REPO_ROOT}/hadoop-${HADOOP_VERSION}"
DEST="${HADOOP_HOME}/bin"
VCPKG_ROOT="/opt/vcpkg"
MAVEN_REPO="${MAVEN_REPO:-/root/.m2/repository}"

# Volume monte depuis l'hote : git refuse les depots au proprietaire different (conteneur only).
git config --global --add safe.directory '*' 2>/dev/null || true

export WINEDEBUG=-all
export _MSPDBSRV_ENDPOINT_=winutils_build
WINE=$(command -v wine64 || command -v wine)

# shellcheck source=/dev/null
source /opt/msvc/bin/x64/msvcenv.sh
export PATH="/usr/local/bin:/opt/msvc/bin/x64:${PATH}"

"${WINE}" wineboot -i >/dev/null 2>&1 || true

# Desktop Wine persistant : evite les blocages MSBuild/mspdbsrv sur pipes herites.
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

  # SDK Windows 10.0.26100+ expose GetFileInformationByName dans winbase.h.
  if [[ -f "${hdr}" ]] && grep -q 'DWORD GetFileInformationByName' "${hdr}"; then
    local f
    for f in "${hdr}" "${win}/libwinutils.c" "${win}/ls.c" "${win}/hardlink.c" "${win}/chmod.c"; do
      [[ -f "$f" ]] && sed -i 's/GetFileInformationByName/Hadoop_Winutils_GetFileInformationByName/g' "$f"
    done
  fi

  # MSVC recent : "final" est un mot-clé C++11, conflit avec #import msxml6.
  if [[ -f "${cfg}" ]] && ! grep -q 'rename("final"' "${cfg}"; then
    sed -i 's|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME")|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME") rename("final", "schemaFinal")|' "${cfg}"
  fi
}

clone_hadoop() {
  local ref_file="${HADOOP_SRC}/.winutils-ref"
  local cached_ref=""
  [[ -f "${ref_file}" ]] && cached_ref="$(cat "${ref_file}")"

  # Clone shallow : un fetch/checkout entre tags echoue souvent (pathspec inconnu).
  if [[ -f "${HADOOP_SRC}/pom.xml" && "${cached_ref}" == "${HADOOP_GIT_REF}" ]]; then
    echo "[build] Sources Hadoop deja sur ${HADOOP_GIT_REF}"
  else
    echo "[build] Clone Hadoop ${HADOOP_GIT_REF}"
    rm -rf "${HADOOP_SRC}"
    git clone --depth 1 --branch "${HADOOP_GIT_REF}" \
      https://github.com/apache/hadoop.git "${HADOOP_SRC}"
    echo "${HADOOP_GIT_REF}" > "${ref_file}"
  fi

  git -C "${HADOOP_SRC}" config core.longpaths true
  patch_hadoop_for_wine "${HADOOP_SRC}"
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

  export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
  export MAVEN_OPTS="-Xmx2048M -Xss128M -Dmaven.repo.local=${MAVEN_REPO}"
  export PATH="${JAVA_HOME}/bin:${PATH}"

  cd "${HADOOP_SRC}"

  echo "[build] Maven: hadoop-common (native-win uniquement)"
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

assemble_dist() {
  bash /docker/assemble-from-release.sh \
    "${HADOOP_VERSION}" \
    "${HADOOP_HOME}" \
    "${HADOOP_SRC}/hadoop-common-project/hadoop-common/target/bin" \
    "/src/.cache/hadoop-releases"
}

echo "[build] Hadoop ${HADOOP_VERSION} ref=${HADOOP_GIT_REF}"
bash /docker/setup-jdk-win32-headers.sh
bash /docker/patch-vcpkg.sh
/docker/install-vcpkg-deps.sh
clone_hadoop
run_maven
assemble_dist
echo "[build] Sortie: ${HADOOP_HOME}/"
ls -la "${DEST}/"

if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "${HOST_UID}:${HOST_GID}" "${HADOOP_HOME}" "${HADOOP_SRC}" 2>/dev/null || true
fi
