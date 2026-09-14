# Native Windows build for winutils (local server / no Docker / no GHA timeout).
# Run from: x64 Native Tools PowerShell for VS 2022 (or this script loads vcvars64).
#
# Usage:
#   .\scripts\build-windows-native.ps1
#   .\scripts\build-windows-native.ps1 -HadoopVersion 3.4.1 -DistProfile lite
#   .\scripts\build-windows-native.ps1 -HadoopVersion 3.4.1 -CreateZip
#
# Prerequisites: Git, Temurin JDK 17 x64, Maven 3.9+, Visual Studio 2022 (C++ desktop), CMake (optional, via VS)

[CmdletBinding()]
param(
    [string]$HadoopVersion = "3.4.1",
    [ValidateSet("lite", "full")][string]$DistProfile = "lite",
    [string]$HadoopSrc = "C:\hadoop-src",
    [string]$VcpkgRoot = "",
    [string]$JavaHome = "",
    [switch]$CreateZip,
    [switch]$SkipVcpkg,
    [switch]$SkipMaven,
    [switch]$SkipAssemble
)

#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$_this = $MyInvocation.MyCommand.Path
if (-not $_this) { throw "Run: .\scripts\build-windows-native.ps1" }
. (Join-Path (Split-Path -Path $_this -Parent) "ps-paths.ps1")
Initialize-WinutilsPaths -CallerPath $_this
$RepoRoot = $script:WinutilsRepoRoot
$ScriptDir = $script:WinutilsScriptDir
$VersionsFile = Join-Path $RepoRoot "versions.conf"
$HadoopHome = Join-Path $RepoRoot "hadoop-$HadoopVersion"
$RefFile = Join-Path $RepoRoot ".hadoop-src-ref"
$CacheDir = Join-Path $RepoRoot ".cache\hadoop-releases"
$VcpkgCommit = if ($env:VCPKG_COMMIT) { $env:VCPKG_COMMIT } else { "2024.12.16" }
if (-not $VcpkgRoot) { $VcpkgRoot = Join-Path $RepoRoot ".cache\vcpkg" }

function Write-Step([string]$Msg) { Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }

function Enable-LongPaths {
    Write-Step "Enable Windows long paths"
    git config --global core.longpaths true
    try {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        Set-ItemProperty -Path $key -Name LongPathsEnabled -Value 1 -Force -ErrorAction Stop
    } catch {
        Write-Warning "LongPathsEnabled requires Administrator; continuing if already enabled"
    }
}

function Import-VsDevEnvironment {
    & (Join-Path $ScriptDir "setup-msvc-env.ps1")
}

function Resolve-GitRef([string]$Version) {
    if (Test-Path $VersionsFile) {
        foreach ($line in Get-Content $VersionsFile) {
            if ($line -match "^\s*#" -or $line -match "^\s*$") { continue }
            $parts = $line -split "=", 2
            if ($parts[0].Trim() -eq $Version) { return $parts[1].Trim() }
        }
    }
    return "rel/release-$Version"
}

function Get-PomVersion([string]$PomPath) {
    $line = Select-String -Path $PomPath -Pattern "<version>" | Select-Object -First 1
    if ($line -match "<version>([^<]+)</version>") { return $matches[1].Trim() }
    throw "Cannot read version from $PomPath"
}

function Clone-Hadoop([string]$GitRef) {
    Write-Step "Clone Hadoop $GitRef -> $HadoopSrc"
    Enable-LongPaths
    $cached = if (Test-Path $RefFile) { Get-Content $RefFile -Raw } else { "" }
    $pom = Join-Path $HadoopSrc "pom.xml"
    if ((Test-Path $pom) -and ($cached.Trim() -eq $GitRef)) {
        $ver = Get-PomVersion $pom
        if ($ver -eq $HadoopVersion) {
            Write-Host "[win] Sources already at $GitRef ($HadoopVersion)"
            return
        }
    }
    if (Test-Path $HadoopSrc) { Remove-Item -Recurse -Force $HadoopSrc }
    New-Item -ItemType Directory -Force -Path (Split-Path $HadoopSrc -Parent) | Out-Null
    git -c core.longpaths=true clone --depth 1 --branch $GitRef `
        https://github.com/apache/hadoop.git $HadoopSrc
    if ($LASTEXITCODE -ne 0) { throw "git clone failed (try C:\hadoop-src + long paths)" }
    Set-Content -Path $RefFile -Value $GitRef -NoNewline
    git -C $HadoopSrc config core.longpaths true
    $srcVer = Get-PomVersion $pom
    if ($srcVer -ne $HadoopVersion) {
        throw "Source version $srcVer != target $HadoopVersion"
    }
}

function Setup-Vcpkg {
    if ($SkipVcpkg) { return }
    Write-Step "vcpkg ($VcpkgRoot)"
    if (-not (Test-Path (Join-Path $VcpkgRoot ".git"))) {
        git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
        git -C $VcpkgRoot checkout $VcpkgCommit
        & (Join-Path $ScriptDir "bootstrap-vcpkg.ps1") -VcpkgRoot $VcpkgRoot
    }
    $marker = Join-Path $VcpkgRoot "installed\x64-windows\include\boost\version.hpp"
    if (-not (Test-Path $marker)) {
        Write-Host "[win] Installing vcpkg packages (30-60 min first time)..."
        & (Join-Path $VcpkgRoot "vcpkg.exe") install `
            boost:x64-windows protobuf:x64-windows openssl:x64-windows zlib:x64-windows
        if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed" }
    }
}

function Find-BashExe {
    $candidates = @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return "bash.exe"
}

function Invoke-MavenNative {
    Write-Step "Maven native-win (hadoop-common + hdfs-native-client)"
    $vcpkgPrefix = Join-Path $VcpkgRoot "installed\x64-windows"
    $toolchain = Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
    $bash = Find-BashExe
    $env:MAVEN_OPTS = if ($env:MAVEN_OPTS) { $env:MAVEN_OPTS } else { "-Xmx4096M -Xss128M" }
    Push-Location $HadoopSrc
    try {
        mvn --batch-mode clean package `
            -pl hadoop-common-project/hadoop-common,hadoop-hdfs-project/hadoop-hdfs-native-client `
            -am `
            -Pnative-win `
            -Dhttps.protocols=TLSv1.2 `
            -DskipTests `
            -DskipDocs `
            "-Dshell-executable=$bash" `
            -Drequire.openssl `
            "-Dopenssl.prefix=$vcpkgPrefix" `
            "-Dcmake.prefix.path=$vcpkgPrefix" `
            "-Dwindows.cmake.toolchain.file=$toolchain" `
            -Dwindows.cmake.build.type=RelWithDebInfo `
            -Dwindows.build.hdfspp.dll=off `
            -Dwindows.no.sasl=on `
            -Duse.platformToolsetVersion=v143
        if ($LASTEXITCODE -ne 0) { throw "Maven build failed" }
    } finally {
        Pop-Location
    }
}

function Write-BuildMeta {
    $javaVer = (java -version 2>&1 | Select-Object -First 1)
    @"
hadoop_version=$HadoopVersion
hadoop_git_ref=$GitRef
build_method=windows-native-powershell
hadoop_src=$HadoopSrc
jdk_runtime=$javaVer
runtime_note=Use Temurin 17 x64 Windows (same family as build JDK)
"@ | Set-Content (Join-Path $HadoopHome ".winutils-build-meta") -Encoding UTF8
}

# --- Main ---
Write-Step "winutils native build $HadoopVersion"
Write-Host "Repo:       $RepoRoot"
Write-Host "HADOOP_SRC: $HadoopSrc"
Write-Host "Output:     $HadoopHome"
Write-Host "Profile:    $DistProfile"

Import-VsDevEnvironment
& (Join-Path $ScriptDir "ensure-maven.ps1")

if ($JavaHome) { $env:JAVA_HOME = $JavaHome }
if (-not $env:JAVA_HOME) {
    throw "JAVA_HOME not set. Example: `$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1-hotspot'"
}
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

foreach ($cmd in @("java", "mvn", "git")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Command not found: $cmd"
    }
}
java -version
mvn -version

$GitRef = Resolve-GitRef $HadoopVersion
Write-Host "Git ref: $GitRef"

Clone-Hadoop $GitRef
Setup-Vcpkg

if (-not $SkipMaven) { Invoke-MavenNative }

$CommonBin = Join-Path $HadoopSrc "hadoop-common-project\hadoop-common\target\bin"
$HdfsBin = Join-Path $HadoopSrc "hadoop-hdfs-project\hadoop-hdfs-native-client\target\bin"

foreach ($pair in @(
    @{ Path = (Join-Path $CommonBin "winutils.exe"); Name = "winutils.exe" },
    @{ Path = (Join-Path $CommonBin "hadoop.dll"); Name = "hadoop.dll" },
    @{ Path = (Join-Path $HdfsBin "hdfs.dll"); Name = "hdfs.dll" }
)) {
    if (-not (Test-Path $pair.Path)) {
        throw "Native build incomplete: missing $($pair.Name)"
    }
}

if (-not $SkipAssemble) {
    Write-Step "Assemble HADOOP_HOME"
    & (Join-Path $ScriptDir "assemble-from-release.ps1") `
        -HadoopVersion $HadoopVersion `
        -HadoopHome $HadoopHome `
        -CommonBin $CommonBin `
        -HdfsBin $HdfsBin `
        -CacheDir $CacheDir `
        -DistProfile $DistProfile
}

Write-BuildMeta

if ($CreateZip) {
    Write-Step "Create zip"
    $zip = Join-Path $RepoRoot "hadoop-$HadoopVersion.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $HadoopHome -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "Zip: $zip"
}

Write-Step "Done"
Write-Host "HADOOP_HOME=$HadoopHome" -ForegroundColor Green
Write-Host @"

Next on this machine (PySpark):
  set JAVA_HOME=$($env:JAVA_HOME)
  set HADOOP_HOME=$HadoopHome
  set PATH=%HADOOP_HOME%\bin;%JAVA_HOME%\bin;%PATH%

"@
