#!/usr/bin/env bash
# Native binaries only (no Apache tarball download).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HADOOP_VERSION="${1:?HADOOP_VERSION required}"
HADOOP_HOME="${2:?HADOOP_HOME required}"
COMMON_BIN="${3:?COMMON_BIN required}"
HDFS_BIN="${4:-}"

[[ -f "${COMMON_BIN}/winutils.exe" && -f "${COMMON_BIN}/hadoop.dll" ]] || {
  echo "[assemble-native] Error: winutils.exe / hadoop.dll missing (${COMMON_BIN})" >&2
  exit 1
}

rm -rf "${HADOOP_HOME}"
mkdir -p "${HADOOP_HOME}/bin"

overlay_dirs=("${COMMON_BIN}")
[[ -n "${HDFS_BIN}" && -d "${HDFS_BIN}" ]] && overlay_dirs+=("${HDFS_BIN}")
bash "${SCRIPT_DIR}/overlay-native-bin.sh" "${HADOOP_HOME}/bin" "${overlay_dirs[@]}"

for req in winutils.exe hadoop.dll hdfs.dll; do
  [[ -f "${HADOOP_HOME}/bin/${req}" ]] || {
    echo "[assemble-native] Error: missing bin/${req}" >&2
    exit 1
  }
done

echo "[assemble-native] OK: ${HADOOP_HOME}/bin/ (native only, no Apache tarball)"
