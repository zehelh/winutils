#!/usr/bin/env bash
# Copy Windows native binaries (cdarlint layout) into HADOOP_HOME/bin/.
set -euo pipefail

HADOOP_BIN="${1:?HADOOP_BIN required}"
shift

mkdir -p "${HADOOP_BIN}"

for native_dir in "$@"; do
  [[ -d "${native_dir}" ]] || continue
  echo "[overlay] Native: ${native_dir}"
  shopt -s nullglob
  for artifact in \
    "${native_dir}/winutils.exe" \
    "${native_dir}/winutils.pdb" \
    "${native_dir}/hadoop.dll" \
    "${native_dir}/hadoop.exp" \
    "${native_dir}/hadoop.lib" \
    "${native_dir}/hadoop.pdb" \
    "${native_dir}/libwinutils.lib" \
    "${native_dir}/libwinutils.pdb" \
    "${native_dir}/hdfs.dll" \
    "${native_dir}/hdfs.exp" \
    "${native_dir}/hdfs.lib" \
    "${native_dir}/hdfs.pdb"; do
    [[ -f "${artifact}" ]] || continue
    cp -f "${artifact}" "${HADOOP_BIN}/"
  done
done

# Linux-only binaries from the Apache release (not needed on Windows).
rm -f \
  "${HADOOP_BIN}/container-executor" \
  "${HADOOP_BIN}/test-container-executor" \
  "${HADOOP_BIN}/oom-listener"
