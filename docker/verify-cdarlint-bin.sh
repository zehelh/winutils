#!/usr/bin/env bash
# Verifie bin/ aligne sur cdarlint (hadoop-3.3.6) + hdfs.dll si present.
set -euo pipefail

HADOOP_BIN="${1:?HADOOP_BIN requis}"
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
  echo "[verify] Erreur: bin/ incomplet (cdarlint):" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [[ "${REQUIRE_HDFS_DLL}" == "1" && ! -f "${HADOOP_BIN}/hdfs.dll" ]]; then
  echo "[verify] Erreur: hdfs.dll absent (LoadLibrary/libhdfs)" >&2
  exit 1
fi

echo "[verify] bin/ OK (cdarlint + scripts release)"
