# Detect MSVC PlatformToolset for Hadoop native-win (v143, v145, ...).
#Requires -Version 5.1
param(
    [string]$Preferred = ""
)

$ErrorActionPreference = "Stop"

function Map-MsvcVersionToToolset([string]$VersionDir) {
    # Folder names like 14.44.35207 under VC/Tools/MSVC
    if ($VersionDir -match '^14\.(3|4)\.') { return 'v143' }
    if ($VersionDir -match '^14\.2\.') { return 'v142' }
    if ($VersionDir -match '^14\.5\.') { return 'v145' }
    if ($VersionDir -match '^14\.6\.') { return 'v145' }
    return $null
}

function Get-InstalledToolsets([string]$VsPath) {
    $msvcRoot = Join-Path $VsPath "VC\Tools\MSVC"
    if (-not (Test-Path $msvcRoot)) { return @() }
    $toolsets = @()
    foreach ($dir in Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending) {
        $ts = Map-MsvcVersionToToolset $dir.Name
        if ($ts -and $toolsets -notcontains $ts) { $toolsets += $ts }
    }
    return $toolsets
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Output "v143"
    exit 0
}

$vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath 2>$null

if (-not $vsPath) {
    Write-Output "v143"
    exit 0
}

$installed = Get-InstalledToolsets $vsPath
if ($Preferred -and ($installed -contains $Preferred)) {
    Write-Output $Preferred
    exit 0
}

foreach ($candidate in @('v143', 'v145', 'v142', 'v144')) {
    if ($installed -contains $candidate) {
        Write-Output $candidate
        exit 0
    }
}

Write-Output "v143"
