# winutils

Windows binaries for Apache Hadoop: `winutils.exe`, `hadoop.dll`, `hdfs.dll`, and `bin/` scripts (`hadoop.cmd`, `hdfs.cmd`, etc.).

Output layout follows [cdarlint/winutils](https://github.com/cdarlint/winutils) and [steveloughran/winutils](https://github.com/steveloughran/winutils).

Built on Linux with Docker, Wine, and MSVC (cross-compile). Native DLLs are overlaid onto the official Apache release tarball.

## Requirements

Host: **Docker** only.

## Quick start

```bash
./build.sh              # default: Hadoop 3.4.1, lite profile
./build.sh 3.4.2
./build.sh 3.5.0 --rebuild-image
```

Output: `hadoop-<version>/` (full `HADOOP_HOME` layout).

### Options

| Option            | Description                                         |
| ----------------- | --------------------------------------------------- |
| `--rebuild-image` | Rebuild the Docker image (needed after JDK changes) |
| `--full`          | Full Apache release (~1.7 GB), no trimming          |
| `--shell`         | Interactive shell inside the container              |
| `-h`, `--help`    | Show help                                           |

## Version alignment

Native DLLs must match both the Hadoop version and the JDK used at runtime.

| Layer             | Must align on                                 |
| ----------------- | --------------------------------------------- |
| Release JARs      | Apache tarball `hadoop-<version>.tar.gz`      |
| Native sources    | Same git ref as the release (`versions.conf`) |
| JNI headers       | OpenJDK 17 (Linux build host)                 |
| `jvm.lib` link    | Temurin **17.0.20.1** x64 Windows             |
| Runtime (Windows) | **Same Temurin build** (e.g. 17.0.20.1 + PySpark) |

After each build, check `hadoop-<version>/.winutils-build-meta` for the exact versions used.

Mismatch (e.g. DLLs built from 3.4.3 sources with 3.4.1 JARs, or JDK 8 link with JDK 17 runtime) causes JNI failures such as `class (null)`.

## Hadoop sources

Apache sources are cloned automatically into `hadoop-src/` from the git ref in `versions.conf`. No manual download.

Add a new version in `versions.conf`:

```
3.4.4=rel/release-3.4.4
```

```bash
./build.sh 3.4.4
```

If a version is missing from `versions.conf`, the default ref is `rel/release-<version>`.

## Distribution profiles

| Profile | Flag      | Size    | Contents                                                  |
| ------- | --------- | ------- | --------------------------------------------------------- |
| `lite`  | (default) | ~270 MB | PySpark-friendly trim: docs, tools, Linux natives removed |
| `full`  | `--full`  | ~1.7 GB | Complete Apache release + Windows native overlay          |

## Caches

| Path                              | Contents                             |
| --------------------------------- | ------------------------------------ |
| Image `winutils-hadoop-wine-msvc` | MSVC, Wine, OpenJDK 17, Maven, vcpkg |
| `.cache/vcpkg-installed/`         | vcpkg `x64-windows` packages         |
| `.cache/hadoop-releases/`         | Cached Apache tarballs               |
| `~/.m2/repository`                | Maven artifacts                      |
| `hadoop-src/`                     | Cloned Hadoop sources                |

## Usage on Windows

Use the **same JDK major version** as the build (Temurin 17 x64):

```cmd
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1-hotspot
set HADOOP_HOME=C:\path\to\hadoop-3.4.1
set PATH=%HADOOP_HOME%\bin;%JAVA_HOME%\bin;%PATH%
```

Use the **exact Temurin version** recorded in `hadoop-<version>/.winutils-build-meta` (`jdk_win_temurin`).

## GitHub Actions (native Windows build)

If JNI still fails with Docker/Wine artifacts (`class (null)`, `LoadLibrary` errors), use a **native Windows** build — the same approach as [steveloughran/winutils](https://github.com/steveloughran/winutils) (real MSVC + Maven `-Pnative-win`, single JDK for compile and link).

The workflow targets a **self-hosted Windows runner** (`runs-on: [self-hosted, Windows, X64]`). Step `Setup Windows toolchain` loads MSVC (`msbuild`, `cl`), installs Maven if missing, and enables long paths.

1. Push this repo to GitHub
2. **Actions** → **Build Windows Native** → **Run workflow**
3. Download the artifact **or** the **GitHub Release** (if `create_release` is enabled)

### Self-hosted Windows server (minimal install)

Manual setup on the server (once):

| Step | Command |
|------|---------|
| 1. Build Tools shell | `winget install Microsoft.VisualStudio.2022.BuildTools` |
| 2. **C++ workload** (Admin) | `.\scripts\install-vs-cpp-workload.ps1` |
| 3. Git for Windows | `winget install Git.Git` |
| 4. Verify toolchain | `.\scripts\setup-windows-runner.ps1 -SkipJavaCheck` |

Step 2 is required: winget only installs the Build Tools installer, not MSVC. The script `install-vs-cpp-workload.ps1` adds *Desktop development with C++* silently (~10-30 min).

Optional: `winget install GitHub.cli` (release duplicate check).

The workflow auto-installs: **Temurin JDK 17**, **Apache Maven** (into tool cache), **vcpkg** + packages, Hadoop sources.

Register the runner with labels `self-hosted`, `Windows`, `X64` (default). Re-run the workflow after pushing workflow updates.

### GitHub Releases (variable version)

Each successful native build can publish:

| Item | Example |
|------|---------|
| Tag | `hadoop-3.4.1` |
| Asset | `hadoop-3.4.1.zip` → contains `hadoop-3.4.1/` (same layout as local build) |
| Manual run | **Build Windows Native** → set version + `create_release: true` |

No PR is created; binaries are attached to the Release (not committed to git).

### Auto-build when Apache publishes a new Hadoop

Workflow **Check Hadoop Releases** (daily cron + manual):

1. Scans [Apache Hadoop downloads](https://downloads.apache.org/hadoop/common/)
2. Compares with existing GitHub Releases (`hadoop-<version>` tags)
3. Triggers **Build Windows Native** for missing versions (default: **1** build per run)

Manual test: **Actions** → **Check Hadoop Releases** → **Run workflow**.

Configure `MIN_VERSION` / `max_builds` in the workflow dispatch inputs. Git ref for builds uses `versions.conf` or defaults to `rel/release-<version>`.

Local Windows (Git Bash + Temurin 17 + Maven + VS Build Tools):

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.20.1-hotspot"
bash scripts/build-windows-native.sh 3.4.1
```

### Windows server (PowerShell, recommended for long builds)

Use this on a dedicated Windows machine when GitHub Actions times out (~2 h) or you need more RAM/CPU. No Docker, no Git Bash required (Git for Windows is still recommended for Maven shell scripts).

**Prerequisites** (manual install only)

| Tool | Notes |
|------|-------|
| Visual Studio 2022 Build Tools | **Desktop development with C++**, MSVC v143 |
| Git for Windows | includes Git Bash |
| [Temurin JDK 17 x64](https://adoptium.net/) | Set `JAVA_HOME` (GHA installs it via `setup-java`) |
| ~30 GB disk | Sources + vcpkg + Maven cache |

Maven is auto-installed by `scripts/ensure-maven.ps1` if missing.

Clone the repo, then from **x64 Native Tools PowerShell for VS 2022** (or plain PowerShell — the script loads `vcvars64` automatically):

```powershell
cd C:\path\to\winutils
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1-hotspot"
.\scripts\build-windows-native.ps1 -HadoopVersion 3.4.1 -DistProfile lite -CreateZip
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-HadoopVersion` | `3.4.1` | Target Hadoop release |
| `-DistProfile` | `lite` | `lite` or `full` |
| `-HadoopSrc` | `C:\hadoop-src` | Short clone path (avoids MAX_PATH) |
| `-CreateZip` | off | Also writes `hadoop-<version>.zip` |
| `-SkipVcpkg` | off | Reuse existing vcpkg install |
| `-SkipMaven` | off | Only assemble (native DLLs already built) |

First run: vcpkg packages (~30–60 min) + Maven native-win (~60–90 min). Subsequent runs reuse caches under `.cache\` and `C:\hadoop-src`.

Output: `hadoop-<version>\` (same layout as Docker/GHA) + optional zip.

### GitHub Actions pricing

| Repo type | Cost |
| --------- | ---- |
| **Public** | Standard GitHub-hosted runners are **free** (fair-use limits apply) |
| **Private** (free plan) | **2,000 minutes/month**; Windows runners bill at **2×** (1 min ≈ 2 min quota) |

A native Hadoop build typically takes **60–120 min** on `windows-latest` (vcpkg + Maven), but can exceed **2 h** and hit runner timeouts. The workflow timeout is **360 min**; for reliability, prefer a local Windows server with `build-windows-native.ps1`. Fine for occasional public-repo builds; watch quota on private repos.

The Docker/Wine path remains available for local Linux builds without using CI minutes.

PySpark example:

```cmd
set PYSPARK_PYTHON=python
set PYSPARK_DRIVER_PYTHON=python
pyspark
```

Classpath is resolved via `%HADOOP_HOME%\bin\hadoop.cmd classpath --glob`.

## `bin/` contents (lite)

Scripts from the Apache release: `hadoop.cmd`, `hdfs.cmd`, `yarn.cmd`, `mapred.cmd`, plus shell stubs.

Native binaries (Wine/MSVC build): `winutils.exe`, `hadoop.dll`, `hdfs.dll`, `.pdb`, `.lib`, `.exp`, `libwinutils.lib`.

## Docker setup (Arch / CachyOS)

```bash
sudo pacman -S docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out and back in after adding yourself to the `docker` group.

## Layout

```
build.sh
versions.conf
scripts/build-windows-native.ps1
scripts/build-windows-native.sh
docker/
hadoop-<version>/          # HADOOP_HOME output
hadoop-<version>/.winutils-build-meta
hadoop-src/
.cache/vcpkg-installed/
.cache/hadoop-releases/
```

## License

Binaries under `hadoop-<version>/` are built from [Apache Hadoop](https://hadoop.apache.org/) under **Apache License 2.0**. You may use, modify, and redistribute them (including commercially) provided you retain `LICENSE` and `NOTICE`.

Build scripts in this repository are under the same license (see `LICENSE`, `NOTICE`).
