# Run native build via Git Bash (avoids WSL bash on LocalSystem runners).
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$HadoopVersion
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command msbuild.exe -ErrorAction SilentlyContinue)) {
    throw "[build] msbuild missing - Setup Windows toolchain step failed"
}

$bash = $env:SHELL_EXECUTABLE
if (-not $bash -or -not (Test-Path $bash)) {
    . (Join-Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) "ps-paths.ps1")
    Refresh-RunnerPath
    $bash = Find-GitBash
}
if (-not $bash) {
    throw "[build] Git Bash not found (set SHELL_EXECUTABLE or install Git for Windows)"
}

Write-Host "[build] bash: $bash"
Write-Host "[build] msbuild: $(cmd /c 'msbuild -version 2>&1 & exit /b 0' | Select-Object -First 1)"

$repo = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent }
Push-Location $repo
try {
    & $bash -eo pipefail ./scripts/invoke-build-native.sh $HadoopVersion
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
