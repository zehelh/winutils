# Apply GetFileInformationByName compatibility shim for modern Windows SDK.
# Required for Hadoop winutils builds on Windows Server 2022 / SDK 10.0.19041+.
# See: https://github.com/notepass/hadoop-native-win-libs
#
# Usage (from Hadoop source root):
#   powershell -ExecutionPolicy Bypass -File path\to\apply-win-compat-shim.ps1

param(
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = "Stop"

$shim = Join-Path $Workspace "hadoop_win_compat.h"
Set-Content -LiteralPath $shim -Encoding ascii -Value @'
#pragma once
#include <windows.h>
#define GetFileInformationByName Hadoop_GetFileInformationByName
'@

$props = Join-Path $Workspace "Directory.Build.props"
Set-Content -LiteralPath $props -Encoding ascii -Value @"
<Project>
  <ItemDefinitionGroup>
    <ClCompile>
      <ForcedIncludeFiles>$shim;%(ForcedIncludeFiles)</ForcedIncludeFiles>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
"@

Write-Host "[apply-win-compat-shim] Created:"
Write-Host "  $shim"
Write-Host "  $props"
