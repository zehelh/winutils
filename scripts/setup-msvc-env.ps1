# Load Visual Studio 2022 MSVC environment (cl, link, msbuild).
#Requires -Version 5.1
# With -ExportToGitHubEnv, persists variables for subsequent GitHub Actions steps.
param([switch]$ExportToGitHubEnv)

$ErrorActionPreference = "Stop"

function Test-MsvcReady {
    return (Get-Command msbuild.exe -ErrorAction SilentlyContinue) -and
           (Get-Command cl.exe -ErrorAction SilentlyContinue)
}

if (Test-MsvcReady) {
    Write-Host "[msvc] Already in PATH: msbuild + cl"
    return
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw @"
[msvc] vswhere not found.
Install Visual Studio 2022 Build Tools with workload 'Desktop development with C++':
  https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022
"@
}

$vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath

if (-not $vsPath) {
    $installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
    $existing = @(& $vswhere -all -products * -property installationPath 2>$null | Where-Object { $_ })
    $hint = @"

[msvc] Visual Studio C++ tools (MSVC v143) not found.
winget only installed Build Tools shell - add the C++ workload:

  Option A (winget, run as Admin):
    winget install Microsoft.VisualStudio.2022.BuildTools --force --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

  Option B (Visual Studio Installer):
    Open 'Visual Studio Installer' -> Modify -> check 'Desktop development with C++' -> Install

"@
    if ($existing.Count -gt 0) {
        $hint += "  Option C (modify existing install at $($existing[0])):`n"
        $hint += "    & `"$installer`" modify --installPath `"$($existing[0])`" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart`n"
    }
    throw $hint.Trim()
}

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
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
        # GITHUB_ENV delimiter syntax for values with special chars
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
    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
    throw "[msvc] Failed to configure toolchain. msbuild=$msbuild cl=$cl"
}

Write-Host "[msvc] OK: $(msbuild -version | Select-Object -First 1)"
Write-Host "[msvc] OK: $(cl 2>&1 | Select-Object -First 1)"
