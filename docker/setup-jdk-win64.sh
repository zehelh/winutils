#!/usr/bin/env bash
# Temurin Windows x64: jvm.lib + jni_md.h (same version as the Linux build JDK).
set -euo pipefail

# shellcheck source=/dev/null
source /docker/jdk-env.sh

MARKER="${JDK_WIN_ROOT}/.temurin-version"
JVM_LIB="${JDK_WIN_ROOT}/lib/jvm.lib"
JNI_MD_DEST="${JAVA_HOME}/include/win32/jni_md.h"

if [[ -f "${MARKER}" && "$(cat "${MARKER}")" == "${TEMURIN_WIN_TAG}" && -f "${JVM_LIB}" && -f "${JNI_MD_DEST}" ]]; then
  echo "[jdk-win64] Already installed: Temurin ${TEMURIN_WIN_TAG}"
  exit 0
fi

echo "[jdk-win64] Downloading Temurin ${TEMURIN_WIN_TAG}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
curl -fsSL --retry 3 -o "${tmpdir}/jdk-win.zip" "${TEMURIN_WIN_URL}"
rm -rf "${JDK_WIN_ROOT}"
unzip -q "${tmpdir}/jdk-win.zip" -d "${tmpdir}/extract"
jdk_dir="$(find "${tmpdir}/extract" -maxdepth 1 -type d -name 'jdk-*' | head -1)"
[[ -n "${jdk_dir}" ]] || jdk_dir="$(find "${tmpdir}/extract" -maxdepth 1 -mindepth 1 -type d | head -1)"

[[ -f "${jdk_dir}/lib/jvm.lib" ]] || {
  echo "[jdk-win64] Error: jvm.lib missing in ${jdk_dir}" >&2
  exit 1
}
[[ -f "${jdk_dir}/include/win32/jni_md.h" ]] || {
  echo "[jdk-win64] Error: include/win32/jni_md.h missing in ${jdk_dir}" >&2
  exit 1
}

mv "${jdk_dir}" "${JDK_WIN_ROOT}"
mkdir -p "${JAVA_HOME}/include/win32"
install -m 644 "${JDK_WIN_ROOT}/include/win32/jni_md.h" "${JNI_MD_DEST}"
echo "${TEMURIN_WIN_TAG}" > "${MARKER}"

echo "[jdk-win64] OK: jvm.lib + jni_md.h Temurin ${TEMURIN_WIN_TAG}"
echo "[jdk-win64]   jvm.lib  -> ${JVM_LIB}"
echo "[jdk-win64]   jni_md.h -> ${JNI_MD_DEST}"
