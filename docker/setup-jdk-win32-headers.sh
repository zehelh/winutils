#!/usr/bin/env bash
# Installe include/win32/jni_md.h pour MSVC (JDK Linux n'a que include/linux/).
set -euo pipefail

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}"
DEST="${JAVA_HOME}/include/win32"
SRC="/docker/jdk-win32/jni_md.h"

[[ -f "${SRC}" ]] || { echo "[jdk] jni_md.h source absent: ${SRC}" >&2; exit 1; }
mkdir -p "${DEST}"
install -m 644 "${SRC}" "${DEST}/jni_md.h"
