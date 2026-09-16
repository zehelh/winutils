# Build winutils.sln directly (diagnostics + clearer MSBuild errors in GHA logs).
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$HadoopSrc,
    [string]$PlatformToolset = "",
    [ValidateSet("minimal", "normal", "detailed")][string]$Verbosity = "minimal"
)

$ErrorActionPreference = "Stop"

if (-not $PlatformToolset) {
    $PlatformToolset = & (Join-Path $PSScriptRoot "detect-msvc-toolset.ps1")
}

$common = Join-Path $HadoopSrc "hadoop-common-project\hadoop-common"
$sln = Join-Path $common "src\main\winutils\winutils.sln"
$outBin = Join-Path $common "target\bin"
$outInt = Join-Path $common "target\winutils"

if (-not (Test-Path $sln)) {
    throw "[winutils-msbuild] Missing solution: $sln"
}

New-Item -ItemType Directory -Force -Path $outBin, $outInt | Out-Null

Write-Host "[winutils-msbuild] PlatformToolset=$PlatformToolset"
Write-Host "[winutils-msbuild] Solution=$sln"

& msbuild.exe $sln `
    /nologo `
    "/v:$Verbosity" `
    /p:Configuration=Release `
    "/p:PlatformToolset=$PlatformToolset" `
    "/p:OutDir=$outBin\" `
    "/p:IntermediateOutputPath=$outInt\" `
    "/p:WsceConfigDir=../etc/hadoop" `
    "/p:WsceConfigFile=wsce-site.xml"

if ($LASTEXITCODE -ne 0) {
    throw "[winutils-msbuild] MSBuild failed (exit $LASTEXITCODE)"
}

Write-Host "[winutils-msbuild] OK"
