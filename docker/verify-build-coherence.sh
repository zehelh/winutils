#!/usr/bin/env bash
# Verify Hadoop + JDK alignment before/after DLL compilation.
set -euo pipefail

HADOOP_VERSION="${HADOOP_VERSION:?HADOOP_VERSION required}"
HADOOP_SRC="${HADOOP_SRC:-/src/hadoop-src}"
HADOOP_HOME="${HADOOP_HOME:-/src/hadoop-${HADOOP_VERSION}}"

# shellcheck source=/dev/null
source /docker/jdk-env.sh

hadoop_src_version() {
  grep -m1 '<version>' "${HADOOP_SRC}/pom.xml" | sed 's|.*<version>\([^<]*\)</version>.*|\1|' | tr -d '[:space:]'
}

jdk_linux_major() {
  java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p'
}

jdk_win_version() {
  [[ -f "${JDK_WIN_ROOT}/.temurin-version" ]] && cat "${JDK_WIN_ROOT}/.temurin-version" || echo "unknown"
}

echo "[verify] === Build coherence ==="
echo "[verify] Target Hadoop     : ${HADOOP_VERSION}"

if [[ -f "${HADOOP_SRC}/pom.xml" ]]; then
  src_ver="$(hadoop_src_version)"
  echo "[verify] Hadoop sources    : ${src_ver}"
  [[ "${src_ver}" == "${HADOOP_VERSION}" ]] || {
    echo "[verify] Error: sources ${src_ver} != build ${HADOOP_VERSION}" >&2
    exit 1
  }
else
  echo "[verify] Error: ${HADOOP_SRC}/pom.xml missing" >&2
  exit 1
fi

linux_major="$(jdk_linux_major)"
echo "[verify] JDK Linux (build)  : ${linux_major} (${JAVA_HOME})"
[[ "${linux_major}" == "${JDK_MAJOR}" ]] || {
  echo "[verify] Error: Linux JDK ${linux_major} != JDK_MAJOR=${JDK_MAJOR}" >&2
  exit 1
}

win_ver="$(jdk_win_version)"
echo "[verify] JDK Windows (link) : Temurin ${win_ver} (${JDK_WIN_ROOT})"
[[ "${win_ver}" == "${TEMURIN_WIN_TAG}" ]] || {
  echo "[verify] Error: Temurin Windows ${win_ver} != ${TEMURIN_WIN_TAG}" >&2
  exit 1
}

[[ -f "${JDK_WIN_ROOT}/lib/jvm.lib" ]] || {
  echo "[verify] Error: jvm.lib missing (${JDK_WIN_ROOT}/lib)" >&2
  exit 1
}

[[ -f "${JAVA_HOME}/include/jni.h" ]] || {
  echo "[verify] Error: jni.h missing in ${JAVA_HOME}/include" >&2
  exit 1
}

[[ -f "${JAVA_HOME}/include/win32/jni_md.h" ]] || {
  echo "[verify] Error: Windows jni_md.h missing (${JAVA_HOME}/include/win32)" >&2
  exit 1
}

jar="${HADOOP_HOME}/share/hadoop/common/hadoop-common-${HADOOP_VERSION}.jar"
if [[ -f "${jar}" ]]; then
  echo "[verify] Release JAR         : hadoop-common-${HADOOP_VERSION}.jar OK"
fi

if [[ "${1:-}" == "--with-native" ]]; then
  common_bin="${HADOOP_SRC}/hadoop-common-project/hadoop-common/target/bin"
  hdfs_bin="${HADOOP_SRC}/hadoop-hdfs-project/hadoop-hdfs-native-client/target/bin"
  for dll in "${common_bin}/hadoop.dll" "${hdfs_bin}/hdfs.dll"; do
    [[ -f "${dll}" ]] || {
      echo "[verify] Error: native binary missing ${dll}" >&2
      exit 1
    }
    echo "[verify] Native OK           : ${dll}"
  done
fi

echo "[verify] OK: Hadoop ${HADOOP_VERSION} + JDK ${JDK_MAJOR} (Temurin ${TEMURIN_WIN_TAG})"
