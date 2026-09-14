# Assemble HADOOP_HOME: Apache tarball + native bin overlay (lite or full).
param(
    [Parameter(Mandatory = $true)][string]$HadoopVersion,
    [Parameter(Mandatory = $true)][string]$HadoopHome,
    [Parameter(Mandatory = $true)][string]$CommonBin,
    [string]$HdfsBin = "",
    [string]$CacheDir = "",
    [ValidateSet("lite", "full", "windows-client")][string]$DistProfile = "lite"
)

#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$_this = $MyInvocation.MyCommand.Path
if ($_this) {
    . (Join-Path (Split-Path -Path $_this -Parent) "ps-paths.ps1")
    Initialize-WinutilsPaths -CallerPath $_this
}

if (-not $CacheDir) {
    $repoRoot = $script:WinutilsRepoRoot
    if (-not $repoRoot -and $_this) {
        $repoRoot = Split-Path -Path (Split-Path -Path $_this -Parent) -Parent
    }
    $CacheDir = Join-Path $repoRoot ".cache\hadoop-releases"
}

$Tarball = "hadoop-$HadoopVersion.tar.gz"
$TarballPath = Join-Path $CacheDir $Tarball
$ParentDir = Split-Path $HadoopHome -Parent

function Test-NativeBin([string]$Dir) {
    foreach ($f in @("winutils.exe", "hadoop.dll")) {
        if (-not (Test-Path (Join-Path $Dir $f))) {
            throw "[assemble] Missing $f in $Dir"
        }
    }
}

Test-NativeBin $CommonBin

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

function Get-Tarball {
    $bases = @(
        "https://downloads.apache.org/hadoop/common/hadoop-$HadoopVersion",
        "https://archive.apache.org/dist/hadoop/common/hadoop-$HadoopVersion"
    )
    foreach ($base in $bases) {
        $url = "$base/$Tarball"
        Write-Host "[assemble] Downloading $url"
        try {
            Invoke-WebRequest -Uri $url -OutFile "$TarballPath.partial" -UseBasicParsing
            Move-Item -Force "$TarballPath.partial" $TarballPath
            try {
                $shaUrl = "$url.sha512"
                $shaFile = "$TarballPath.sha512"
                Invoke-WebRequest -Uri $shaUrl -OutFile $shaFile -UseBasicParsing
                $expected = ((Get-Content $shaFile -Raw) -replace '(?s).*=\s*', '').Trim().ToLower()
                $actual = (Get-FileHash $TarballPath -Algorithm SHA512).Hash.ToLower()
                if ($expected -ne $actual) { throw "SHA512 mismatch" }
                Write-Host "[assemble] SHA512 OK"
            } catch {
                Write-Warning "[assemble] No SHA512 verification"
            }
            return
        } catch {
            Remove-Item "$TarballPath.partial" -ErrorAction SilentlyContinue
        }
    }
    throw "[assemble] Unable to download $Tarball"
}

if (-not (Test-Path $TarballPath)) { Get-Tarball }
else { Write-Host "[assemble] Cached tarball $TarballPath" }

if (Test-Path $HadoopHome) { Remove-Item -Recurse -Force $HadoopHome }
New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
& tar -xzf $TarballPath -C $ParentDir
if (-not (Test-Path $HadoopHome)) { throw "[assemble] $HadoopHome missing after extract" }

function Copy-NativeArtifacts([string[]]$NativeDirs) {
    $HadoopBin = Join-Path $HadoopHome "bin"
    New-Item -ItemType Directory -Force -Path $HadoopBin | Out-Null
    $names = @(
        "winutils.exe", "winutils.pdb", "hadoop.dll", "hadoop.exp", "hadoop.lib", "hadoop.pdb",
        "libwinutils.lib", "libwinutils.pdb", "hdfs.dll", "hdfs.exp", "hdfs.lib", "hdfs.pdb"
    )
    foreach ($dir in $NativeDirs) {
        if (-not (Test-Path $dir)) { continue }
        Write-Host "[overlay] Native: $dir"
        foreach ($name in $names) {
            $src = Join-Path $dir $name
            if (Test-Path $src) { Copy-Item -Force $src $HadoopBin }
        }
    }
    foreach ($linuxBin in @("container-executor", "test-container-executor", "oom-listener")) {
        Remove-Item (Join-Path $HadoopBin $linuxBin) -ErrorAction SilentlyContinue
    }
}

$dirs = @($CommonBin)
if ($HdfsBin -and (Test-Path $HdfsBin)) { $dirs += $HdfsBin }
Copy-NativeArtifacts $dirs

function Trim-Lite {
    Write-Host "[assemble] Trimming lite profile..."
    $before = (Get-ChildItem $HadoopHome -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $remove = @(
        "share\doc", "share\hadoop\tools", "share\hadoop\client", "lib\native", "lib", "include",
        "sbin", "licenses-binary", "share\hadoop\common\jdiff", "share\hadoop\common\sources",
        "share\hadoop\hdfs\sources", "share\hadoop\yarn\sources", "share\hadoop\yarn\webapps",
        "share\hadoop\yarn\test", "share\hadoop\mapreduce\sources"
    )
    foreach ($rel in $remove) {
        $p = Join-Path $HadoopHome $rel
        if (Test-Path $p) { Remove-Item -Recurse -Force $p }
    }
    $after = (Get-ChildItem $HadoopHome -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $savedMb = [math]::Round(($before - $after) / 1MB)
    Write-Host "[assemble] Lite profile: ~${savedMb} MB removed"
}

switch ($DistProfile) {
    { $_ -in "lite", "windows-client" } { Trim-Lite }
    "full" { Write-Host "[assemble] Full profile: untrimmed Apache release" }
    default { throw "Unknown profile: $DistProfile" }
}

$bin = Join-Path $HadoopHome "bin"
$required = @(
    "hadoop.cmd", "hdfs.cmd", "yarn.cmd", "mapred.cmd", "hadoop.dll", "winutils.exe", "hdfs.dll"
)
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $bin $f))) { throw "[verify] Missing bin\$f" }
}
Write-Host "[verify] bin/ OK"

foreach ($req in @(
    "libexec\hadoop-config.cmd",
    "etc\hadoop\core-site.xml",
    "share\hadoop\common\hadoop-common-$HadoopVersion.jar",
    "bin\hadoop.cmd"
)) {
    if (-not (Test-Path (Join-Path $HadoopHome $req))) {
        throw "[assemble] Incomplete layout, missing: $req"
    }
}

$sizeMb = [math]::Round((Get-ChildItem $HadoopHome -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB)
Write-Host "[assemble] HADOOP_HOME: $HadoopHome ($DistProfile, ~${sizeMb} MB)"
