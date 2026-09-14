# Prepare a Windows self-hosted runner (or GHA job) for native Hadoop builds.
param([switch]$ExportToGitHubEnv)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Host "=== Windows runner setup ==="

# Long paths (best-effort; HKLM needs admin)
git config --global core.longpaths true
try {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
    Set-ItemProperty -Path $key -Name LongPathsEnabled -Value 1 -Force -ErrorAction Stop
    Write-Host "[paths] LongPathsEnabled=1"
} catch {
    Write-Warning "[paths] LongPathsEnabled needs Administrator (continuing if already set)"
}

# Work dirs used by build (avoid MAX_PATH)
foreach ($dir in @("C:\hadoop-src", "C:\vcpkg")) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

& (Join-Path $PSScriptRoot "ensure-maven.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv
& (Join-Path $PSScriptRoot "setup-msvc-env.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv

# Git Bash for Maven shell scripts
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

# gh CLI optional (release check step)
if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "[toolchain] gh CLI not found — install with: winget install GitHub.cli (or set create_release: false)"
}

Write-Host "=== Toolchain verification ==="
foreach ($cmd in @("java", "git", "mvn.cmd")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "[toolchain] Missing: $cmd"
    }
}
java -version
mvn -version
git --version
msbuild -version | Select-Object -First 1
cl 2>&1 | Select-Object -First 1
Write-Host "=== Ready ==="
