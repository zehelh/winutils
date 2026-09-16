# Native binaries only (no Apache tarball download).
param(
    [Parameter(Mandatory = $true)][string]$HadoopVersion,
    [Parameter(Mandatory = $true)][string]$HadoopHome,
    [Parameter(Mandatory = $true)][string]$CommonBin,
    [string]$HdfsBin = ""
)

$ErrorActionPreference = "Stop"
foreach ($f in @("winutils.exe", "hadoop.dll")) {
    if (-not (Test-Path (Join-Path $CommonBin $f))) {
        throw "[assemble-native] Missing $f in $CommonBin"
    }
}

if (Test-Path $HadoopHome) { Remove-Item -Recurse -Force $HadoopHome }
$bin = Join-Path $HadoopHome "bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$names = @(
    "winutils.exe", "winutils.pdb", "hadoop.dll", "hadoop.exp", "hadoop.lib", "hadoop.pdb",
    "libwinutils.lib", "libwinutils.pdb", "hdfs.dll", "hdfs.exp", "hdfs.lib", "hdfs.pdb"
)
foreach ($dir in @($CommonBin, $HdfsBin)) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    Write-Host "[overlay] Native: $dir"
    foreach ($name in $names) {
        $src = Join-Path $dir $name
        if (Test-Path $src) { Copy-Item -Force $src $bin }
    }
}

foreach ($req in @("winutils.exe", "hadoop.dll", "hdfs.dll")) {
    if (-not (Test-Path (Join-Path $bin $req))) {
        throw "[assemble-native] Missing bin\$req"
    }
}
Write-Host "[assemble-native] OK: $bin (native only, no Apache tarball)"
