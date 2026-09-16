#!/usr/bin/env bash
# Windows SDK 10.0.26100+ declares GetFileInformationByName in winbase.h;
# Hadoop winutils declares the same symbol with a different signature (C2733 in config.cpp).
set -euo pipefail

HADOOP_SRC="${1:?HADOOP_SRC required}"
WIN="${HADOOP_SRC}/hadoop-common-project/hadoop-common/src/main/winutils"
HDR="${WIN}/include/winutils.h"
CFG="${WIN}/config.cpp"
RENAME="Hadoop_Winutils_GetFileInformationByName"

if [[ ! -d "${WIN}" ]]; then
  echo "[patch] skip: winutils sources not found under ${HADOOP_SRC}"
  exit 0
fi

# Directory.Build.props ForcedIncludeFiles is unreliable with Hadoop vcxproj — rename in source.
if [[ -f "${HDR}" ]]; then
  if grep -q "${RENAME}" "${HDR}"; then
    echo "[patch] GetFileInformationByName rename already applied"
  elif grep -q 'GetFileInformationByName' "${HDR}"; then
    echo "[patch] Renaming Hadoop GetFileInformationByName -> ${RENAME} (SDK 10.0.26100+)"
    while IFS= read -r -d '' file; do
      sed -i 's/GetFileInformationByName/Hadoop_Winutils_GetFileInformationByName/g' "${file}"
    done < <(grep -rl 'GetFileInformationByName' "${WIN}" \
      \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -print0)
  fi
fi

# MSVC C++11: "final" conflicts with #import msxml6 in config.cpp
if [[ -f "${CFG}" ]] && grep -q '#import "msxml6.dll"' "${CFG}" && ! grep -q 'rename("final"' "${CFG}"; then
  echo "[patch] msxml6 #import: rename final keyword for MSVC"
  sed -i 's|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME")|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME") rename("final", "schemaFinal")|' "${CFG}"
fi

# Remove stale shim files from older patch versions (confusing if left on disk).
rm -f "${HADOOP_SRC}/hadoop_win_compat.h" "${HADOOP_SRC}/Directory.Build.props"

echo "[patch] winutils SDK compatibility OK"
