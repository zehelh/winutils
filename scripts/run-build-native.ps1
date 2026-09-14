# Run native build via Git Bash (avoids WSL bash on LocalSystem runners).
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$HadoopVersion
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# Reload MSVC into this process (GITHUB_ENV PATH may not propagate fully into Git Bash).
& (Join-Path $scriptDir "setup-msvc-env.ps1")

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

Write-Host "[build] bash: $bash"
Write-Host "[build] msbuild: $(cmd /c 'msbuild.exe -version 2>&1 & exit /b 0' | Select-Object -First 1)"

$repo = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Split-Path $scriptDir -Parent }
Push-Location $repo
try {
    & $bash -eo pipefail ./scripts/build-windows-native.sh $HadoopVersion
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
