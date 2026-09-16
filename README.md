# winutils

Windows binaries for Apache Hadoop: `winutils.exe`, `hadoop.dll`, `hdfs.dll`, and `bin/` scripts (`hadoop.cmd`, `hdfs.cmd`, etc.).

Output layout follows [cdarlint/winutils](https://github.com/cdarlint/winutils) and [steveloughran/winutils](https://github.com/steveloughran/winutils).

**Native Windows build** (MSVC + Maven `-Pnative-win`): DLLs are compiled on Windows, then packaged according to **package mode**.

## Package modes

| Mode      | Output | Use case |
| --------- | ------ | -------- |
| `native`  | `bin/` only (`winutils.exe`, `hadoop.dll`, `hdfs.dll`) | Default — scheduled builds, drop-in native libs |
| `tarball` | Lite `HADOOP_HOME` (~270 MB): Apache release + native overlay, trimmed for PySpark | Full layout without docs/tools/Linux libs |
| `full`    | Complete Apache release + native overlay | Entire official distribution |

Scheduled builds (`Check Hadoop Releases`) use **`native`** only (no Apache tarball download).

Manual builds can choose the mode in the **Build Windows Native** workflow. Release tags are suffixed so variants do not overwrite each other:

| Mode     | GitHub Release tag        |
| -------- | ------------------------- |
| `native` | `hadoop-<version>`        |
| `tarball`| `hadoop-<version>-tarball`|
| `full`   | `hadoop-<version>-full`   |

## `hadoop-<version>/` contents

| Item                   | Description                                                                 |
| ---------------------- | --------------------------------------------------------------------------- |
| `bin/`                 | Native binaries (+ `.cmd` scripts when using `tarball` or `full`)           |
| `share/`, `etc/`       | JARs and config (`tarball` / `full` only)                                 |
| `.winutils-build-meta` | JDK / git ref / package mode used for the build                             |

## Build requirements

| Tool                | Notes                                                 |
| ------------------- | ----------------------------------------------------- |
| Windows 10/11 x64   | Self-hosted runner or dedicated machine               |
| VS 2022 Build Tools | **Desktop development with C++** workload (MSVC v143) |
| Git for Windows     | Bash for Maven helper scripts                         |
| Temurin JDK 17 x64  | Same major at runtime (e.g. 17.0.20)                  |
| ~30 GB disk         | `C:\hadoop-src`, `C:\vcpkg`, Maven cache              |

Maven and vcpkg are installed automatically by the scripts when missing.

## Local build (PowerShell)

From **PowerShell** (the script loads `vcvars64` if needed):

```powershell
cd C:\path\to\winutils
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1-hotspot"
.\scripts\build-windows-native.ps1 -HadoopVersion 3.4.1 -PackageMode native -CreateZip
```

| Parameter        | Default         | Description                         |
| ---------------- | --------------- | ----------------------------------- |
| `-HadoopVersion` | `3.4.1`         | Hadoop version                      |
| `-PackageMode`   | `native`        | `native`, `tarball`, or `full`      |
| `-HadoopSrc`     | `C:\hadoop-src` | Source clone path (avoids MAX_PATH) |
| `-CreateZip`     | off             | Also writes `hadoop-<version>.zip`  |
| `-SkipVcpkg`     | off             | Reuse existing vcpkg install        |
| `-SkipMaven`     | off             | Assemble only (DLLs already built)  |

Git Bash alternative (after MSVC setup):

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.20.1-hotspot"
bash scripts/build-windows-native.sh 3.4.1
# tarball or full:
WINUTILS_PACKAGE_MODE=tarball bash scripts/build-windows-native.sh 3.4.1
```

**First run**: vcpkg (~30–60 min) + Maven native (~60 min). Later runs reuse caches.

## Self-hosted runner setup (once)

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools
winget install Git.Git
# Admin — C++ workload:
.\scripts\install-vs-cpp-workload.ps1
# Verify:
.\scripts\setup-windows-runner.ps1 -SkipJavaCheck
```

Register the runner with labels `self-hosted`, `Windows`, `X64`.

## GitHub Actions

**Build Windows Native** workflow (`build-windows-native.yml`):

1. Actions → **Build Windows Native** → Run workflow
2. Choose **package mode** (`native`, `tarball`, or `full`)
3. Download the artifact or the **GitHub Release** (tag depends on mode, see table above)

**Check Hadoop Releases** (daily cron): detects new Apache versions and triggers **`native`** builds for missing `hadoop-<version>` release tags.

## Hadoop versions

Git refs in `versions.conf`:

```
3.4.1=rel/release-3.4.1
3.4.2=rel/release-3.4.2
```

Add a line and build the new version. If missing from `versions.conf`, default ref is `rel/release-<version>`.

## JDK / JNI alignment

| Layer              | Must match                                 |
| ------------------ | ------------------------------------------ |
| Release JARs       | `hadoop-<version>.tar.gz` tarball          |
| Native sources     | Git ref in `versions.conf`                 |
| JNI compile + link | Temurin **17** x64 (same build as runtime) |

Check `hadoop-<version>/.winutils-build-meta` after each build. A different JDK (e.g. 17.0.20 vs 21) can cause JNI failures (`class (null)`, `LoadLibrary` errors).

## Usage on Windows

```cmd
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1-hotspot
set HADOOP_HOME=C:\path\to\hadoop-3.4.1
set PATH=%HADOOP_HOME%\bin;%JAVA_HOME%\bin;%PATH%
```

PySpark:

```cmd
set PYSPARK_PYTHON=python
set PYSPARK_DRIVER_PYTHON=python
pyspark
```

Classpath via `%HADOOP_HOME%\bin\hadoop.cmd classpath --glob`.

## Caches

| Path                      | Contents                       |
| ------------------------- | ------------------------------ |
| `C:\hadoop-src`           | Cloned Apache sources          |
| `C:\vcpkg`                | vcpkg + `x64-windows` packages |
| `.cache/hadoop-releases/` | Cached Apache tarballs         |
| `~/.m2/repository`        | Maven cache                    |

## Repository layout

```
scripts/
  build-windows-native.ps1    # Local build entry (PowerShell)
  build-windows-native.sh     # Build entry (Git Bash / GHA)
  setup-windows-runner.ps1    # Self-hosted runner toolchain
  assemble-native-only.sh     # bin/ only (no tarball)
  assemble-from-release.sh    # Apache tarball + native overlay
versions.conf
.github/workflows/
  build-windows-native.yml
  check-hadoop-releases.yml
hadoop-<version>/             # HADOOP_HOME output (not committed)
```

## License

Binaries under `hadoop-<version>/` are from [Apache Hadoop](https://hadoop.apache.org/) under **Apache License 2.0**. Scripts in this repo: see `LICENSE`, `NOTICE`.
