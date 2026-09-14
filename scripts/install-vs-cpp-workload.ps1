# Install MSVC C++ workload on Visual Studio 2022 Build Tools (or Community).
# Requires: Administrator. Run once on the self-hosted runner machine.
#
# Usage (PowerShell as Admin):
#   cd H:\winutils
#   .\scripts\install-vs-cpp-workload.ps1
#
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [int]$WaitMinutes = 90
)

$ErrorActionPreference = "Stop"

$VsInstallerDir = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer"
$VsInstaller = Join-Path $VsInstallerDir "vs_installer.exe"
$VsWhere = Join-Path $VsInstallerDir "vswhere.exe"
$WorkloadId = "Microsoft.VisualStudio.Workload.VCTools"
$AcceptExitCodes = @(0, 3010, 1641)

function Write-Step([string]$Msg) {
    Write-Host ""
    Write-Host "==> $Msg" -ForegroundColor Cyan
}

function Test-MsvcInstalled {
    if (-not (Test-Path $VsWhere)) { return $false }
    $path = & $VsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return [bool]$path
}

function Get-VsInstallInfo {
    if (-not (Test-Path $VsWhere)) {
        throw "vswhere not found. Run: winget install Microsoft.VisualStudio.2022.BuildTools"
    }

    $withCpp = & $VsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($withCpp) {
        return @{ Path = $withCpp.Trim(); HasCpp = $true; ProductId = (Get-VsProductId $withCpp) }
    }

    $anyPath = & $VsWhere -latest -products * -property installationPath 2>$null
    if ($anyPath) {
        return @{ Path = $anyPath.Trim(); HasCpp = $false; ProductId = (Get-VsProductId $anyPath) }
    }

    throw "No Visual Studio installation found. Run: winget install Microsoft.VisualStudio.2022.BuildTools"
}

function Get-VsProductId([string]$InstallPath) {
    return (& $VsWhere -products * -property productId -path $InstallPath 2>$null | Select-Object -First 1)
}

function Test-AcceptExitCode([int]$Code) {
    return $AcceptExitCodes -contains $Code
}

function Invoke-VsInstaller([string[]]$InstallerArgs) {
    if (-not (Test-Path $VsInstaller)) {
        throw "vs_installer.exe not found: $VsInstaller"
    }
    $display = ($InstallerArgs | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    Write-Host "  vs_installer.exe $display" -ForegroundColor DarkGray

    $proc = Start-Process -FilePath $VsInstaller -ArgumentList $InstallerArgs -PassThru -Wait -NoNewWindow
    return $proc.ExitCode
}

function Update-VsInstaller {
    Write-Step "Update Visual Studio Installer (required before modify)"
    # Do NOT pass --noUpdateInstaller here.
    $code = Invoke-VsInstaller @("update", "--quiet", "--norestart")
    if (Test-AcceptExitCode $code) {
        Write-Host "  Installer update finished (exit $code)." -ForegroundColor Green
        return
    }
    Write-Warning "  Installer update exit code $code (continuing anyway)"
}

function Install-ViaInstallerModify([string]$InstallPath) {
    Write-Step "Add C++ workload via vs_installer modify"
    Write-Host "  Install path: $InstallPath"
    Write-Host "  Workload:     $WorkloadId"

    # NOTE: --wait is ONLY valid on bootstrapper (vs_BuildTools.exe), NOT on vs_installer.exe (exit 87).
    $code = Invoke-VsInstaller @(
        "modify",
        "--installPath", $InstallPath,
        "--add", $WorkloadId,
        "--includeRecommended",
        "--quiet",
        "--norestart"
    )
    return $code
}

function Find-VsBootstrapper {
    $names = @("vs_BuildTools.exe", "vs_setup.exe")
    foreach ($name in $names) {
        $hit = Get-ChildItem -Path $VsInstallerDir -Filter $name -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Install-ViaBootstrapper {
    Write-Step "Fallback: bootstrapper with --wait (vs_BuildTools.exe)"
    $bootstrapper = Find-VsBootstrapper
    if (-not $bootstrapper) {
        Write-Warning "  Bootstrapper not found under $VsInstallerDir"
        return 999
    }

    Write-Host "  Bootstrapper: $bootstrapper"
    $args = @(
        "--wait",
        "--passive",
        "--norestart",
        "--nocache",
        "--add", $WorkloadId,
        "--includeRecommended"
    )
    $display = ($args | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    Write-Host "  $display" -ForegroundColor DarkGray

    $proc = Start-Process -FilePath $bootstrapper -ArgumentList $args -PassThru -Wait -NoNewWindow
    return $proc.ExitCode
}

function Install-ViaWinget {
    Write-Step "Fallback: winget with C++ workload override"
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "  winget not available"
        return 999
    }

    $override = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    Write-Host "  winget install Microsoft.VisualStudio.2022.BuildTools --force --override `"$override`""

    $proc = Start-Process -FilePath "winget.exe" -ArgumentList @(
        "install", "Microsoft.VisualStudio.2022.BuildTools",
        "--force",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--override", $override
    ) -PassThru -Wait -NoNewWindow
    return $proc.ExitCode
}

function Wait-MsvcReady([int]$TimeoutMinutes) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Step "Waiting for MSVC v143 (timeout ${TimeoutMinutes} min)"
    while ((Get-Date) -lt $deadline) {
        if (Test-MsvcInstalled) {
            Write-Host "  MSVC C++ tools detected." -ForegroundColor Green
            return
        }
        Write-Host ("  ... installing ({0:HH:mm:ss})" -f (Get-Date)) -ForegroundColor DarkGray
        Start-Sleep -Seconds 30
    }
    throw "Timeout waiting for MSVC. Open Visual Studio Installer and check for errors."
}

function Show-ManualHelp {
    Write-Host ""
    Write-Host "Automatic install failed. Manual fix:" -ForegroundColor Yellow
    Write-Host "  1. Start menu -> Visual Studio Installer"
    Write-Host "  2. Click Modify on 'Visual Studio Build Tools 2022'"
    Write-Host "  3. Check 'Desktop development with C++' -> Install"
    Write-Host "  4. Re-run: .\scripts\setup-windows-runner.ps1 -SkipJavaCheck"
    Write-Host ""
    Write-Host "Logs: %TEMP%\dd_setup_*_logs" -ForegroundColor DarkGray
}

Write-Step "Visual Studio C++ workload installer"

if (Test-MsvcInstalled) {
    Write-Host "MSVC C++ tools already installed. Nothing to do." -ForegroundColor Green
    exit 0
}

$info = Get-VsInstallInfo
if ($info.HasCpp) {
    Write-Host "MSVC already present at $($info.Path)." -ForegroundColor Green
    exit 0
}

Update-VsInstaller

$exitCode = Install-ViaInstallerModify -InstallPath $info.Path
if (-not (Test-AcceptExitCode $exitCode)) {
    Write-Warning "vs_installer modify failed with exit code $exitCode"
    if ($exitCode -eq 87) {
        Write-Warning "Exit 87 = invalid parameter (--wait is not allowed on vs_installer modify; script fixed)"
    }
    $exitCode = Install-ViaBootstrapper
}

if (-not (Test-AcceptExitCode $exitCode)) {
    Write-Warning "Bootstrapper exit code $exitCode"
    $exitCode = Install-ViaWinget
}

if (-not (Test-AcceptExitCode $exitCode) -and -not (Test-MsvcInstalled)) {
    Show-ManualHelp
    throw "All automatic install methods failed (last exit code: $exitCode)."
}

Wait-MsvcReady -TimeoutMinutes $WaitMinutes

Write-Step "Next step"
Write-Host "  .\scripts\setup-windows-runner.ps1 -SkipJavaCheck"
Write-Host ""
Write-Host "Done." -ForegroundColor Green
