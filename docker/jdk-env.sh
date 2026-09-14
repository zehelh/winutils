#!/usr/bin/env bash
# Single JDK configuration for the entire native build (JNI headers + jvm.lib).
# Must match the Windows JDK used at runtime (e.g. Temurin 17.0.20.1 for PySpark).
set -euo pipefail

export JDK_MAJOR="${JDK_MAJOR:-17}"
export TEMURIN_WIN_TAG="${TEMURIN_WIN_TAG:-jdk-17.0.20.1+1}"
export TEMURIN_WIN_VERSION="${TEMURIN_WIN_VERSION:-17.0.20.1_1}"
export TEMURIN_WIN_URL="https://github.com/adoptium/temurin17-binaries/releases/download/${TEMURIN_WIN_TAG}/OpenJDK17U-jdk_x64_windows_hotspot_${TEMURIN_WIN_VERSION}.zip"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-${JDK_MAJOR}-openjdk-amd64}"
export JDK_WIN_ROOT="${JDK_WIN_ROOT:-/opt/jdk-win64}"
export JAVA_WIN64_HOME="${JDK_WIN_ROOT}"

if [[ ! -d "${JAVA_HOME}" ]]; then
  echo "[jdk] Error: JAVA_HOME not found: ${JAVA_HOME}" >&2
  echo "[jdk] Rebuild the Docker image (openjdk-${JDK_MAJOR}-jdk)." >&2
  exit 1
fi

export PATH="${JAVA_HOME}/bin:${PATH}"
