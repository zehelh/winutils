# Path helpers - compatible Windows PowerShell 5.1+ and PowerShell 7+.
#Requires -Version 5.1

function Initialize-WinutilsPaths {
    param([string]$CallerPath = "")

    if (-not $CallerPath) {
        $CallerPath = $MyInvocation.MyCommand.Path
    }

    $script:WinutilsScriptDir = $PSScriptRoot
    if (-not $script:WinutilsScriptDir -and $CallerPath) {
        $script:WinutilsScriptDir = Split-Path -Path $CallerPath -Parent
    }
    if (-not $script:WinutilsScriptDir) {
        $cwd = (Get-Location).Path
        $candidate = Join-Path $cwd "scripts\setup-msvc-env.ps1"
        if (Test-Path $candidate) {
            $script:WinutilsRepoRoot = $cwd
            $script:WinutilsScriptDir = Join-Path $cwd "scripts"
            return
        }
    }
    if (-not $script:WinutilsScriptDir) {
        throw "[winutils] Cannot resolve scripts/ directory. Run: .\scripts\setup-windows-runner.ps1"
    }
    $script:WinutilsRepoRoot = Split-Path -Path $script:WinutilsScriptDir -Parent
}
