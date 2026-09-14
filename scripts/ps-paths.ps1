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

function Refresh-RunnerPath {
    param([switch]$ExportToGitHubEnv)

    # Runner Windows service caches PATH at startup; reload Machine + User after winget installs.
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machine -and $user) {
        $env:Path = "$machine;$user"
    } elseif ($machine) {
        $env:Path = $machine
    }

    if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "PATH=$env:Path"
    }
}

function Find-GitBash {
    $candidates = @()

    if ($env:WINUTILS_GIT_ROOT) {
        $candidates += Join-Path $env:WINUTILS_GIT_ROOT "bin\bash.exe"
    }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        # git.exe may live in .../Git/cmd (Git for Windows) or .../Git/bin
        $gitDir = Split-Path -Path $git.Source -Parent
        $gitRoot = Split-Path -Path $gitDir -Parent
        $leaf = Split-Path -Path $gitDir -Leaf
        if ($leaf -eq "cmd") {
            $candidates += Join-Path $gitRoot "bin\bash.exe"
            $candidates += Join-Path $gitRoot "usr\bin\bash.exe"
        } else {
            $candidates += Join-Path $gitDir "bash.exe"
            $candidates += Join-Path $gitRoot "bin\bash.exe"
            $candidates += Join-Path $gitRoot "usr\bin\bash.exe"
        }
    }

    $candidates += @(
        "H:\Programs\Git\bin\bash.exe",
        (Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
    )

    foreach ($regKey in @(
        "HKLM:\SOFTWARE\GitForWindows",
        "HKLM:\SOFTWARE\WOW6432Node\GitForWindows"
    )) {
        try {
            $install = (Get-ItemProperty -Path $regKey -ErrorAction Stop).InstallPath
            if ($install) {
                $candidates += Join-Path $install "bin\bash.exe"
            }
        } catch {
            # optional registry key
        }
    }

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if ($path -and (Test-Path -Path $path)) {
            return $path
        }
    }

    return $null
}
