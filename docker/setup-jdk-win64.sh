#!/usr/bin/env bash
# JDK Windows x64 : jvm.lib requis pour lier hdfs.dll (libhdfs JNI).
set -euo pipefail

JDK_WIN_ROOT="${JDK_WIN_ROOT:-/opt/jdk-win64}"
MARKER="${JDK_WIN_ROOT}/lib/jvm.lib"
TEMURIN_VERSION="8u504b01"
TEMURIN_TAG="jdk8u504-b01"
TEMURIN_URL="https://github.com/adoptium/temurin8-binaries/releases/download/${TEMURIN_TAG}/OpenJDK8U-jdk_x64_windows_hotspot_${TEMURIN_VERSION}.zip"

if [[ -f "${MARKER}" ]]; then
  echo "[jdk-win64] Deja installe: ${JDK_WIN_ROOT}"
  exit 0
fi

echo "[jdk-win64] Telechargement Temurin ${TEMURIN_VERSION}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
curl -fsSL --retry 3 -o "${tmpdir}/jdk-win.zip" "${TEMURIN_URL}"
rm -rf "${JDK_WIN_ROOT}"
unzip -q "${tmpdir}/jdk-win.zip" -d "${tmpdir}/extract"
jdk_dir="$(find "${tmpdir}/extract" -maxdepth 1 -type d -name 'jdk8u*' | head -1)"
[[ -n "${jdk_dir}" ]] || jdk_dir="$(find "${tmpdir}/extract" -maxdepth 1 -mindepth 1 -type d | head -1)"
[[ -f "${jdk_dir}/lib/jvm.lib" ]] || {
  echo "[jdk-win64] Erreur: jvm.lib absent dans ${jdk_dir}" >&2
  exit 1
}
mv "${jdk_dir}" "${JDK_WIN_ROOT}"
echo "[jdk-win64] OK: ${JDK_WIN_ROOT}/lib/jvm.lib"
