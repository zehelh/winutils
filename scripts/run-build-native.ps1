# Run native build via Git Bash (avoids WSL bash on LocalSystem runners).
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$HadoopVersion,
    [ValidateSet("native", "tarball", "full")][string]$PackageMode = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
. (Join-Path $scriptDir "ps-paths.ps1")
Initialize-WinutilsPaths -CallerPath $MyInvocation.MyCommand.Path

# Reload MSVC into this process (GITHUB_ENV PATH may not propagate fully into Git Bash).
# vcvars64 overwrites VCPKG_ROOT with VS bundled vcpkg — preserve runner paths first.
$runnerPaths = @{
    VCPKG_ROOT = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "H:\vcpkg" }
    HADOOP_SRC = if ($env:HADOOP_SRC) { $env:HADOOP_SRC } else { "H:\hadoop-src" }
    MAVEN_ARGS = $env:MAVEN_ARGS
}
& (Join-Path $scriptDir "setup-msvc-env.ps1")
foreach ($name in $runnerPaths.Keys) {
    if ($runnerPaths[$name]) {
        Set-Item -Path "env:$name" -Value $runnerPaths[$name]
    }
}
Ensure-PythonPath

$hadoopSrcWin = $runnerPaths.HADOOP_SRC
& (Join-Path $scriptDir "patch-hadoop-winutils-sdk.ps1") -HadoopSrc $hadoopSrcWin
$toolset = & (Join-Path $scriptDir "detect-msvc-toolset.ps1")
$env:PLATFORM_TOOLSET = $toolset
Write-Host "[build] PLATFORM_TOOLSET=$toolset"

if (-not (Get-Command msbuild.exe -ErrorAction SilentlyContinue)) {
    throw "[build] msbuild missing - Setup Windows toolchain step failed"
}

$bash = $env:SHELL_EXECUTABLE
if (-not $bash -or -not (Test-Path $bash)) {
    . (Join-Path $scriptDir "ps-paths.ps1")
    Refresh-RunnerPath
    $bash = Find-GitBash
}
if (-not $bash) {
    throw "[build] Git Bash not found (set SHELL_EXECUTABLE or install Git for Windows)"
}

# Git Bash: keep Windows PATH entries (MSBuild, cl.exe live there).
$env:MSYS2_PATH_TYPE = "inherit"
$env:SHELL_EXECUTABLE = $bash
if ($PackageMode) {
    $env:WINUTILS_PACKAGE_MODE = $PackageMode
} elseif ($env:WINUTILS_PACKAGE_MODE) {
    # keep GITHUB_ENV value from workflow
} else {
    $env:WINUTILS_PACKAGE_MODE = "native"
}

Write-Host "[build] bash: $bash"
Write-Host "[build] VCPKG_ROOT=$env:VCPKG_ROOT"
Write-Host "[build] HADOOP_SRC=$env:HADOOP_SRC"
Write-Host "[build] msbuild: $(cmd /c 'msbuild.exe -version 2>&1 & exit /b 0' | Select-Object -First 1)"

$repo = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Split-Path $scriptDir -Parent }
Push-Location $repo
try {
    & $bash -eo pipefail ./scripts/build-windows-native.sh $HadoopVersion
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
