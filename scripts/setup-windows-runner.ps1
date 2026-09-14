# Prepare a Windows self-hosted runner (or GHA job) for native Hadoop builds.
param(
    [switch]$ExportToGitHubEnv,
    [switch]$SkipJavaCheck
)

$ErrorActionPreference = "Stop"
$_caller = $MyInvocation.MyCommand.Path
if ($_caller) {
    $_scriptDir = Split-Path -LiteralPath $_caller -Parent
} elseif ($PSScriptRoot) {
    $_scriptDir = $PSScriptRoot
} elseif (Test-Path -LiteralPath (Join-Path (Get-Location).Path "scripts\ps-paths.ps1")) {
    $_scriptDir = Join-Path (Get-Location).Path "scripts"
} else {
    throw "Run from repo root: pwsh -File scripts/setup-windows-runner.ps1"
}
. (Join-Path $_scriptDir "ps-paths.ps1")
Initialize-WinutilsPaths -CallerPath $_caller

Write-Host "=== Windows runner setup ==="
Write-Host "Repo: $script:WinutilsRepoRoot"

git config --global core.longpaths true
try {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
    Set-ItemProperty -Path $key -Name LongPathsEnabled -Value 1 -Force -ErrorAction Stop
    Write-Host "[paths] LongPathsEnabled=1"
} catch {
    Write-Warning "[paths] LongPathsEnabled needs Administrator (continuing if already set)"
}

foreach ($dir in @("C:\hadoop-src", "C:\vcpkg")) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

& (Join-Path $script:WinutilsScriptDir "ensure-maven.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv
& (Join-Path $script:WinutilsScriptDir "setup-msvc-env.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv

$bashCandidates = @(
    "${env:ProgramFiles}\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    throw "[toolchain] Git Bash not found. Install Git for Windows: winget install Git.Git"
}
Write-Host "[toolchain] bash: $bash"

if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "SHELL_EXECUTABLE=$bash"
}

if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "[toolchain] gh CLI not found - install with: winget install GitHub.cli (or set create_release: false)"
}

Write-Host "=== Toolchain verification ==="
foreach ($cmd in @("git", "mvn.cmd")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "[toolchain] Missing: $cmd"
    }
}

if (-not $SkipJavaCheck -and -not (Get-Command java -ErrorAction SilentlyContinue)) {
    if ($ExportToGitHubEnv) {
        throw "[toolchain] Missing: java (setup-java should run before this step in GHA)"
    }
    Write-Warning "[toolchain] java not on PATH - OK for MSVC check; GHA installs JDK via setup-java"
} elseif (Get-Command java -ErrorAction SilentlyContinue) {
    java -version
}

mvn -version
git --version
msbuild -version | Select-Object -First 1
cl 2>&1 | Select-Object -First 1
Write-Host "=== Ready ==="
