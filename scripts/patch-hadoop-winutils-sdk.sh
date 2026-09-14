#!/usr/bin/env bash
# Windows SDK 10.0.26100+ declares GetFileInformationByName in winbase.h;
# Hadoop winutils declares the same symbol with a different signature (C2733 in config.cpp).
# Shim: force-include windows.h then macro-rename Hadoop's symbol (notepass/hadoop-native-win-libs).
set -euo pipefail

HADOOP_SRC="${1:?HADOOP_SRC required}"
WIN="${HADOOP_SRC}/hadoop-common-project/hadoop-common/src/main/winutils"
CFG="${WIN}/config.cpp"
COMPAT_H="${HADOOP_SRC}/hadoop_win_compat.h"
PROPS="${HADOOP_SRC}/Directory.Build.props"

if [[ ! -d "${WIN}" ]]; then
  echo "[patch] skip: winutils sources not found under ${HADOOP_SRC}"
  exit 0
fi

cat > "${COMPAT_H}" <<'EOF'
#pragma once
#include <windows.h>
#define GetFileInformationByName Hadoop_GetFileInformationByName
EOF

# MSBuild discovers Directory.Build.props walking up from each vcxproj.
cat > "${PROPS}" <<EOF
<Project>
  <ItemDefinitionGroup>
    <ClCompile>
      <ForcedIncludeFiles>${COMPAT_H};%(ForcedIncludeFiles)</ForcedIncludeFiles>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
EOF
echo "[patch] SDK shim: ${COMPAT_H} + ${PROPS}"

# MSVC C++11: "final" conflicts with #import msxml6 in config.cpp
if [[ -f "${CFG}" ]] && grep -q '#import "msxml6.dll"' "${CFG}" && ! grep -q 'rename("final"' "${CFG}"; then
  echo "[patch] msxml6 #import: rename final keyword for MSVC"
  sed -i 's|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME")|#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME") rename("final", "schemaFinal")|' "${CFG}"
fi

echo "[patch] winutils SDK compatibility OK"
