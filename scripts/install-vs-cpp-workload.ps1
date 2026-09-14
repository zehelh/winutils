# Install MSVC C++ workload on Visual Studio 2022 Build Tools (or Community).
# Requires: Administrator. Run once on the self-hosted runner machine.
#
# Usage (PowerShell as Admin):
#   cd H:\winutils
#   .\scripts\install-vs-cpp-workload.ps1
#   .\scripts\install-vs-cpp-workload.ps1 -WaitMinutes 45
#
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [int]$WaitMinutes = 60
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Msg) {
    Write-Host ""
    Write-Host "==> $Msg" -ForegroundColor Cyan
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-MsvcInstalled {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return [bool]$path
}

function Get-VsInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere not found. Install Visual Studio 2022 Build Tools first."
    }

    $withCpp = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($withCpp) { return @{ Path = $withCpp; HasCpp = $true } }

    $any = & $vswhere -latest -products * -property installationPath 2>$null
    if ($any) { return @{ Path = $any; HasCpp = $false } }

    throw "No Visual Studio installation found. Run: winget install Microsoft.VisualStudio.2022.BuildTools"
}

function Install-VsCppWorkload([string]$InstallPath) {
    $installer = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vs_installer.exe"
    if (-not (Test-Path $installer)) {
        throw "vs_installer.exe not found at $installer"
    }

    Write-Step "Installing C++ workload (passive, may take 10-30 min)"
    Write-Host "Install path: $InstallPath"
    Write-Host "Components:   Microsoft.VisualStudio.Workload.VCTools + Recommended"

    $args = @(
        "modify",
        "--installPath", $InstallPath,
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended",
        "--passive",
        "--norestart",
        "--wait"
    )

    $proc = Start-Process -FilePath $installer -ArgumentList $args -PassThru -Wait
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "vs_installer exited with code $($proc.ExitCode). Open Visual Studio Installer and add 'Desktop development with C++' manually."
    }
    if ($proc.ExitCode -eq 3010) {
        Write-Host "Install complete (reboot recommended, not required now)." -ForegroundColor Yellow
    }
}

function Wait-MsvcReady([int]$TimeoutMinutes) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Step "Waiting for MSVC v143 (timeout ${TimeoutMinutes} min)"
    while ((Get-Date) -lt $deadline) {
        if (Test-MsvcInstalled) {
            Write-Host "MSVC C++ tools detected." -ForegroundColor Green
            return
        }
        Write-Host ("  ... still installing ({0:HH:mm:ss})" -f (Get-Date)) -ForegroundColor DarkGray
        Start-Sleep -Seconds 30
    }
    throw "Timeout waiting for MSVC. Check Visual Studio Installer for progress or errors."
}

Write-Step "Visual Studio C++ workload installer"

if (-not (Test-Admin)) {
    throw "Run PowerShell as Administrator to install Visual Studio components."
}

if (Test-MsvcInstalled) {
    Write-Host "MSVC C++ tools already installed. Nothing to do." -ForegroundColor Green
    exit 0
}

$info = Get-VsInstallPath
if ($info.HasCpp) {
    Write-Host "MSVC C++ tools already installed at $($info.Path)." -ForegroundColor Green
    exit 0
}

Install-VsCppWorkload -InstallPath $info.Path
Wait-MsvcReady -TimeoutMinutes $WaitMinutes

Write-Step "Verify with setup-windows-runner.ps1"
Write-Host "  cd H:\winutils"
Write-Host "  .\scripts\setup-windows-runner.ps1 -SkipJavaCheck"
Write-Host ""
Write-Host "Done." -ForegroundColor Green
