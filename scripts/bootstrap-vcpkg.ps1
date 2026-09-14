# Bootstrap vcpkg with MSVC in PATH (VS 2022 Build Tools).
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$VcpkgRoot
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

& (Join-Path $scriptDir "setup-msvc-env.ps1")

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($vsPath) {
        $env:VCPKG_VISUAL_STUDIO_PATH = $vsPath
        Write-Host "[vcpkg] VCPKG_VISUAL_STUDIO_PATH=$vsPath"
    }
}

$bootstrap = Join-Path $VcpkgRoot "scripts\bootstrap.ps1"
if (-not (Test-Path $bootstrap)) {
    throw "[vcpkg] Missing $bootstrap (clone vcpkg first)"
}

Write-Host "[vcpkg] Bootstrapping..."
Push-Location $VcpkgRoot
try {
    & $bootstrap -disableMetrics
    if (-not (Test-Path (Join-Path $VcpkgRoot "vcpkg.exe"))) {
        throw "[vcpkg] bootstrap.ps1 finished but vcpkg.exe is missing"
    }
    Write-Host "[vcpkg] OK: $(Join-Path $VcpkgRoot 'vcpkg.exe')"
} finally {
    Pop-Location
}
exit 0
