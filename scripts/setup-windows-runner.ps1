# Prepare a Windows self-hosted runner (or GHA job) for native Hadoop builds.
#Requires -Version 5.1
param(
    [switch]$ExportToGitHubEnv,
    [switch]$SkipJavaCheck
)

$ErrorActionPreference = "Stop"
$_this = $MyInvocation.MyCommand.Path
if (-not $_this) { throw "Run: .\scripts\setup-windows-runner.ps1" }
. (Join-Path (Split-Path -Path $_this -Parent) "ps-paths.ps1")
Initialize-WinutilsPaths -CallerPath $_this

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
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Setup stopped: install C++ tools then re-run this script." -ForegroundColor Red
    exit 1
}

$bashCandidates = @(
    "${env:ProgramFiles}\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    throw "[toolchain] Git Bash not found. Install: winget install Git.Git"
}
Write-Host "[toolchain] bash: $bash"

if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "SHELL_EXECUTABLE=$bash"
}

if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "[toolchain] gh CLI not found - optional: winget install GitHub.cli"
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
    Write-Warning "[toolchain] java not on PATH - OK for MSVC check only"
} elseif (Get-Command java -ErrorAction SilentlyContinue) {
    java -version
}

mvn -version
git --version
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
Write-Host "[toolchain] $(cmd /c 'msbuild -version 2>&1' | Select-Object -First 1)"
Write-Host "[toolchain] $(cmd /c 'cl 2>&1' | Select-Object -First 1)"
$ErrorActionPreference = $prevEap
Write-Host "=== Ready ==="
