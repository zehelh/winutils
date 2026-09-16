# Windows SDK 10.0.26100+ / Hadoop winutils compatibility patch.
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$HadoopSrc
)

$ErrorActionPreference = "Stop"
$Rename = "Hadoop_Winutils_GetFileInformationByName"
$Win = Join-Path $HadoopSrc "hadoop-common-project\hadoop-common\src\main\winutils"
$Hdr = Join-Path $Win "include\winutils.h"
$Cfg = Join-Path $Win "config.cpp"

if (-not (Test-Path $Win)) {
    Write-Host "[patch] skip: winutils not found under $HadoopSrc"
    exit 0
}

if (Test-Path $Hdr) {
    $hdrText = Get-Content -Raw $Hdr
    if ($hdrText -match [regex]::Escape($Rename)) {
        Write-Host "[patch] GetFileInformationByName rename already applied"
    } elseif ($hdrText -match 'GetFileInformationByName') {
        Write-Host "[patch] Renaming Hadoop GetFileInformationByName -> $Rename (SDK 10.0.26100+)"
        $files = Get-ChildItem -Path $Win -Recurse -Include *.c, *.cpp, *.h -File |
            Where-Object { (Get-Content -Raw $_.FullName) -match 'GetFileInformationByName' }
        foreach ($file in $files) {
            (Get-Content -Raw $file.FullName) `
                -replace 'GetFileInformationByName', $Rename |
                Set-Content -Path $file.FullName -NoNewline
        }
    }
}

if (Test-Path $Cfg) {
    $cfgText = Get-Content -Raw $Cfg
    if ($cfgText -match '#import "msxml6.dll"' -and $cfgText -notmatch 'rename\("final"') {
        Write-Host "[patch] msxml6 #import: rename final keyword for MSVC"
        $cfgText = $cfgText -replace `
            '#import "msxml6.dll" exclude\("ISequentialStream", "_FILETIME"\)', `
            '#import "msxml6.dll" exclude("ISequentialStream", "_FILETIME") rename("final", "schemaFinal")'
        Set-Content -Path $Cfg -Value $cfgText -NoNewline
    }
}

Remove-Item -Force -ErrorAction SilentlyContinue `
    (Join-Path $HadoopSrc "hadoop_win_compat.h"), `
    (Join-Path $HadoopSrc "Directory.Build.props")

Write-Host "[patch] winutils SDK compatibility OK"
