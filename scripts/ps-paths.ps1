# Resolve scripts/ and repo root (works with pwsh -File, dot-source, or cwd = repo root).
function Initialize-WinutilsPaths {
    param([string]$CallerPath = $MyInvocation.PSCommandPath)

    $script:WinutilsScriptDir = $PSScriptRoot
    if (-not $script:WinutilsScriptDir -and $CallerPath) {
        $script:WinutilsScriptDir = Split-Path -LiteralPath $CallerPath -Parent
    }
    if (-not $script:WinutilsScriptDir) {
        $cwd = (Get-Location).Path
        $candidate = Join-Path $cwd "scripts\setup-msvc-env.ps1"
        if (Test-Path -LiteralPath $candidate) {
            $script:WinutilsRepoRoot = $cwd
            $script:WinutilsScriptDir = Join-Path $cwd "scripts"
            return
        }
    }
    if (-not $script:WinutilsScriptDir) {
        throw @"
[winutils] Cannot resolve scripts/ directory.
Run from the repo root:
  pwsh -File scripts/setup-windows-runner.ps1
"@
    }
    $script:WinutilsRepoRoot = Split-Path -LiteralPath $script:WinutilsScriptDir -Parent
}
