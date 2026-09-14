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

function Find-PythonExe {
    # Windows installs python.exe (not always python3). Search common layout + py launcher.
    $candidates = @()

    foreach ($root in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python")
        (Join-Path ${env:ProgramFiles} "Python312")
        (Join-Path ${env:ProgramFiles(x86)} "Python312")
    )) {
        if (-not (Test-Path $root)) { continue }
        if (Test-Path (Join-Path $root "python.exe")) {
            $candidates += (Join-Path $root "python.exe")
        }
        Get-ChildItem -Path $root -Directory -Filter "Python*" -ErrorAction SilentlyContinue | ForEach-Object {
            $exe = Join-Path $_.FullName "python.exe"
            if (Test-Path $exe) { $candidates += $exe }
        }
    }

    $pyCmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $candidates += "py.exe|-3"
    }

    foreach ($entry in ($candidates | Select-Object -Unique)) {
        if ($entry -like "py.exe|*") {
            return $entry
        }
        if ($entry -and (Test-Path -Path $entry)) {
            return $entry
        }
    }

    return $null
}

function Ensure-PythonPath {
    param([switch]$ExportToGitHubEnv)

    if (Get-Command python3.exe -ErrorAction SilentlyContinue) {
        Write-Host "[toolchain] python3: $(Get-Command python3.exe).Source"
        return
    }

    $found = Find-PythonExe
    if (-not $found) {
        Write-Warning "[toolchain] Python not found (optional for winutils build; patch scripts use awk/sed)"
        return
    }

    if ($found -like "py.exe|*") {
        $shimDir = Join-Path $script:WinutilsScriptDir "win-bin"
        New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
        $py3 = Join-Path $shimDir "python3.cmd"
        @(
            '@echo off',
            'py -3 %*'
        ) | Set-Content -Path $py3 -Encoding ASCII
        $env:Path = "$shimDir;$env:Path"
        Write-Host "[toolchain] python3 shim: $py3 (via py -3)"
    } else {
        $pyHome = Split-Path -Path $found -Parent
        $pyScripts = Join-Path $pyHome "Scripts"
        $paths = @($pyHome)
        if (Test-Path $pyScripts) { $paths += $pyScripts }
        $shimDir = Join-Path $script:WinutilsScriptDir "win-bin"
        New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
        if (-not (Test-Path (Join-Path $pyHome "python3.exe"))) {
            $py3 = Join-Path $shimDir "python3.cmd"
            @(
                '@echo off',
                "`"$found`" %*"
            ) | Set-Content -Path $py3 -Encoding ASCII
            $paths = @($shimDir) + $paths
            Write-Host "[toolchain] python3 shim: $py3 -> $found"
        }
        $env:Path = (($paths -join ";") + ";" + $env:Path)
        Write-Host "[toolchain] python: $found"
    }

    if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "PATH=$env:Path"
    }
}
