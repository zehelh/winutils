# Load Visual Studio 2022 MSVC environment (cl, link, msbuild).
#Requires -Version 5.1
param([switch]$ExportToGitHubEnv)

$ErrorActionPreference = "Stop"

function Get-ToolVersionLine([string]$Cmd) {
    # Native tools (cl.exe) print version to stderr; avoid PS error records with ErrorAction Stop.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        return (cmd /c $Cmd 2>&1 | Select-Object -First 1)
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Test-MsvcReady {
    return (Get-Command msbuild.exe -ErrorAction SilentlyContinue) -and
           (Get-Command cl.exe -ErrorAction SilentlyContinue)
}

function Write-MsvcInstallHelp {
    $repoRoot = $null
    if ($script:WinutilsRepoRoot) { $repoRoot = $script:WinutilsRepoRoot }
    $installScript = if ($repoRoot) {
        Join-Path $repoRoot "scripts\install-vs-cpp-workload.ps1"
    } else {
        ".\scripts\install-vs-cpp-workload.ps1"
    }

    Write-Host ""
    Write-Host "[msvc] ERROR: C++ build tools not installed." -ForegroundColor Red
    Write-Host "[msvc] winget installs Build Tools shell only - add the C++ workload once:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Open PowerShell as Administrator" -ForegroundColor White
    Write-Host "  2. cd H:\winutils" -ForegroundColor White
    Write-Host "  3. .\scripts\install-vs-cpp-workload.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or GUI: Visual Studio Installer -> Modify -> Desktop development with C++" -ForegroundColor DarkGray
    Write-Host ""
}

if (Test-MsvcReady) {
    Write-Host "[msvc] Already in PATH: msbuild + cl"
    return
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-MsvcInstallHelp
    throw "[msvc] vswhere not found - install Visual Studio 2022 Build Tools first."
}

$vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath 2>$null

if (-not $vsPath) {
    Write-MsvcInstallHelp
    exit 1
}

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    Write-MsvcInstallHelp
    throw "[msvc] vcvars64.bat not found: $vcvars"
}

Write-Host "[msvc] Loading $vcvars"

$envLines = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $envLines) {
    if ($line -notmatch "^([^=]+)=(.*)$") { continue }
    $name = $matches[1]
    $value = $matches[2]
    Set-Item -Path "env:$name" -Value $value
    if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
        if ($value -match "[\r\n%]") {
            $delim = "MSVCENV_${name}_$(Get-Random)"
            Add-Content -Path $env:GITHUB_ENV -Value "${name}<<${delim}"
            Add-Content -Path $env:GITHUB_ENV -Value $value
            Add-Content -Path $env:GITHUB_ENV -Value $delim
        } else {
            Add-Content -Path $env:GITHUB_ENV -Value "${name}=$value"
        }
    }
}

if (-not (Test-MsvcReady)) {
    Write-MsvcInstallHelp
    throw "[msvc] vcvars64 loaded but msbuild/cl still missing."
}

Write-Host "[msvc] OK: $(Get-ToolVersionLine 'msbuild -version')"
Write-Host "[msvc] OK: $(Get-ToolVersionLine 'cl 2>&1')"
