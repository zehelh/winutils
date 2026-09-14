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

1. Push this repo to GitHub
2. **Actions** → **Build Windows Native** → **Run workflow**
3. Download the `hadoop-<version>-windows-native` artifact

Local Windows (Git Bash + Temurin 17 + Maven + VS Build Tools):

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.20.1-hotspot"
bash scripts/build-windows-native.sh 3.4.1
```

### GitHub Actions pricing

| Repo type | Cost |
| --------- | ---- |
| **Public** | Standard GitHub-hosted runners are **free** (fair-use limits apply) |
| **Private** (free plan) | **2,000 minutes/month**; Windows runners bill at **2×** (1 min ≈ 2 min quota) |

A native Hadoop build typically takes **60–120 min** on `windows-latest` (vcpkg + Maven). Fine for occasional public-repo builds; watch quota on private repos.

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
