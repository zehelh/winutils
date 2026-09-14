#!/usr/bin/env bash
# Verify bin/ matches cdarlint layout (hadoop-3.3.6) + hdfs.dll when present.
set -euo pipefail

HADOOP_BIN="${1:?HADOOP_BIN required}"
REQUIRE_HDFS_DLL="${REQUIRE_HDFS_DLL:-1}"

required=(
  hadoop.cmd hdfs.cmd yarn.cmd mapred.cmd
  hadoop hadoop.dll winutils.exe
  hadoop.exp hadoop.lib hadoop.pdb
  libwinutils.lib libwinutils.pdb
  winutils.pdb
  hdfs yarn mapred
)

missing=()
for f in "${required[@]}"; do
  [[ -e "${HADOOP_BIN}/${f}" ]] || missing+=("${f}")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "[verify] Error: incomplete bin/ (cdarlint):" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [[ "${REQUIRE_HDFS_DLL}" == "1" && ! -f "${HADOOP_BIN}/hdfs.dll" ]]; then
  echo "[verify] Error: hdfs.dll missing (LoadLibrary/libhdfs)" >&2
  exit 1
fi

echo "[verify] bin/ OK (cdarlint + release scripts)"
