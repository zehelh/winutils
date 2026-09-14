# Install Apache Maven into RUNNER_TOOL_CACHE (or .cache/maven) if not on PATH.
param(
    [string]$MavenVersion = "3.9.9",
    [switch]$ExportToGitHubEnv
)

$ErrorActionPreference = "Stop"

if (Get-Command mvn.cmd -ErrorAction SilentlyContinue) {
    Write-Host "[maven] Already on PATH: $(mvn -version | Select-Object -First 1)"
    return
}

$toolRoot = if ($env:RUNNER_TOOL_CACHE) { $env:RUNNER_TOOL_CACHE } else { Join-Path (Split-Path $PSScriptRoot -Parent) ".cache" }
$mavenHome = Join-Path $toolRoot "maven-$MavenVersion"
$mvnCmd = Join-Path $mavenHome "bin\mvn.cmd"

if (-not (Test-Path $mvnCmd)) {
    Write-Host "[maven] Downloading Apache Maven $MavenVersion..."
    New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
    $zip = Join-Path $toolRoot "apache-maven-$MavenVersion-bin.zip"
    $url = "https://archive.apache.org/dist/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $toolRoot -Force
    $extracted = Join-Path $toolRoot "apache-maven-$MavenVersion"
    if (Test-Path $mavenHome) { Remove-Item -Recurse -Force $mavenHome }
    Rename-Item $extracted $mavenHome
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
}

$env:MAVEN_HOME = $mavenHome
$env:PATH = "$mavenHome\bin;$env:PATH"

if ($ExportToGitHubEnv -and $env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "MAVEN_HOME=$mavenHome"
    Add-Content -Path $env:GITHUB_ENV -Value "PATH=$env:PATH"
}

Write-Host "[maven] OK: $(mvn -version | Select-Object -First 1)"
