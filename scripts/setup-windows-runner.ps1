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
Refresh-RunnerPath -ExportToGitHubEnv:$ExportToGitHubEnv

# Custom Git install (e.g. H:\Programs\Git) - add cmd to PATH for this job if needed
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    foreach ($gitCmdDir in @(
        "H:\Programs\Git\cmd",
        (Join-Path ${env:ProgramFiles} "Git\cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd")
    )) {
        if (Test-Path (Join-Path $gitCmdDir "git.exe")) {
            $env:Path = "$gitCmdDir;$env:Path"
            break
        }
    }
    if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "PATH=$env:Path"
    }
}

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

foreach ($dir in @("H:\hadoop-src", "H:\vcpkg", "H:\m2\repository")) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

& (Join-Path $script:WinutilsScriptDir "ensure-maven.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv

& (Join-Path $script:WinutilsScriptDir "setup-msvc-env.ps1") -ExportToGitHubEnv:$ExportToGitHubEnv
if (-not (Get-Command msbuild.exe -ErrorAction SilentlyContinue) -or
    -not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Setup stopped: install C++ tools then re-run this script." -ForegroundColor Red
    exit 1
}

$bash = Find-GitBash
if (-not $bash) {
    Write-Host ""
    Write-Host "[toolchain] Git Bash not found on runner PATH." -ForegroundColor Red
    Write-Host "  Install: winget install Git.Git" -ForegroundColor Yellow
    Write-Host "  Then restart the runner service (PATH is cached at service start):" -ForegroundColor Yellow
    Write-Host "    Stop-Service actions.runner.* ; Start-Service actions.runner.*" -ForegroundColor Yellow
    throw "[toolchain] Git Bash not found"
}
Write-Host "[toolchain] bash: $bash"

Ensure-PythonPath -ExportToGitHubEnv:$ExportToGitHubEnv

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
    cmd /c "java -version 2>&1 & exit /b 0" 2>&1 | ForEach-Object { Write-Host $_ }
}

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
cmd /c "mvn -version 2>&1 & exit /b 0" 2>&1 | ForEach-Object { Write-Host $_ }
cmd /c "git --version 2>&1 & exit /b 0" 2>&1 | ForEach-Object { Write-Host $_ }
Write-Host "[toolchain] $(cmd /c 'msbuild -version 2>&1 & exit /b 0' | Select-Object -First 1)"
Write-Host "[toolchain] $(cmd /c 'cl 2>&1 & exit /b 0' | Select-Object -First 1)"
$ErrorActionPreference = $prevEap
Write-Host "=== Ready ==="
exit 0
