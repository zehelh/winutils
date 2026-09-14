#!/usr/bin/env bash
# Full HADOOP_HOME: Apache release tarball + native winutils.exe / hadoop.dll / hdfs.dll overlay.
set -euo pipefail

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HADOOP_VERSION="${1:?HADOOP_VERSION required}"
HADOOP_HOME="${2:?HADOOP_HOME required}"
COMMON_BIN="${3:?COMMON_BIN (hadoop-common target/bin) required}"
HDFS_BIN="${4:-}"
CACHE_DIR="${5:-/src/.cache/hadoop-releases}"
# lite (default): trimmed for PySpark / hadoop.cmd classpath --glob
# full: complete Apache release (~1.7 GB)
DIST_PROFILE="${HADOOP_DIST_PROFILE:-lite}"

TARBALL="hadoop-${HADOOP_VERSION}.tar.gz"
TARBALL_PATH="${CACHE_DIR}/${TARBALL}"
PARENT_DIR="$(dirname "${HADOOP_HOME}")"

[[ -f "${COMMON_BIN}/winutils.exe" ]] || {
  echo "[assemble] Error: winutils.exe missing (${COMMON_BIN})" >&2
  exit 1
}
[[ -f "${COMMON_BIN}/hadoop.dll" ]] || {
  echo "[assemble] Error: hadoop.dll missing (${COMMON_BIN})" >&2
  exit 1
}

mkdir -p "${CACHE_DIR}"

download_tarball() {
  local bases=(
    "https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}"
    "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}"
  )
  local base url

  for base in "${bases[@]}"; do
    url="${base}/${TARBALL}"
    echo "[assemble] Downloading ${url}"
    if curl -fsSL --retry 3 --retry-delay 2 -o "${TARBALL_PATH}.partial" "${url}"; then
      mv -f "${TARBALL_PATH}.partial" "${TARBALL_PATH}"
      if curl -fsSL --retry 2 -o "${TARBALL_PATH}.sha512" "${url}.sha512" 2>/dev/null; then
        local expected actual
        # Apache format: SHA512 (file) = <hash>
        expected="$(sed -n 's/.*= //p' "${TARBALL_PATH}.sha512" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        actual="$(sha512sum "${TARBALL_PATH}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
        if [[ "${expected}" != "${actual}" ]]; then
          echo "[assemble] Error: invalid SHA512 for ${TARBALL}" >&2
          rm -f "${TARBALL_PATH}"
          exit 1
        fi
        echo "[assemble] SHA512 OK"
      else
        echo "[assemble] Warning: no SHA512 verification" >&2
      fi
      return 0
    fi
    rm -f "${TARBALL_PATH}.partial"
  done

  echo "[assemble] Error: unable to download hadoop-${HADOOP_VERSION}.tar.gz" >&2
  exit 1
}

if [[ ! -f "${TARBALL_PATH}" ]]; then
  download_tarball
else
  echo "[assemble] Cached tarball ${TARBALL_PATH}"
fi

is_windows_env() {
  [[ "${OS:-}" == "Windows_NT" ]] || [[ "${RUNNER_OS:-}" == "Windows" ]]
}

extract_release_tarball() {
  local name="hadoop-${HADOOP_VERSION}"
  local -a tar_args=(-xzf "${TARBALL_PATH}" -C "${PARENT_DIR}")

  if is_windows_env; then
    # Apache tarball ships Linux lib/native as symlinks; Git Bash tar cannot create them.
    # Lite profile removes lib/ anyway; Windows HADOOP_HOME uses our native bin/ overlay.
    tar_args+=(--exclude="${name}/lib/native")
    echo "[assemble] Windows: excluding ${name}/lib/native (Linux symlinks)"
  fi

  if tar "${tar_args[@]}"; then
    return 0
  fi

  # Fallback: partial extract is OK if bin/ layout exists (symlink-only failures).
  if is_windows_env && [[ -d "${HADOOP_HOME}/bin" ]]; then
    echo "[assemble] Warning: tar errors ignored (Windows symlink limits)" >&2
    return 0
  fi
  return 1
}

rm -rf "${HADOOP_HOME}"
mkdir -p "${PARENT_DIR}"
extract_release_tarball || {
  echo "[assemble] Error: failed to extract ${TARBALL}" >&2
  exit 1
}

[[ -d "${HADOOP_HOME}" ]] || {
  echo "[assemble] Error: ${HADOOP_HOME} missing after extraction" >&2
  exit 1
}

overlay_dirs=("${COMMON_BIN}")
[[ -n "${HDFS_BIN}" && -d "${HDFS_BIN}" ]] && overlay_dirs+=("${HDFS_BIN}")
bash "${DOCKER_DIR}/overlay-native-bin.sh" "${HADOOP_HOME}/bin" "${overlay_dirs[@]}"

trim_lite() {
  local before after saved
  before="$(du -sb "${HADOOP_HOME}" | awk '{print $1}')"

  echo "[assemble] Trimming lite profile..."
  rm -rf \
    "${HADOOP_HOME}/share/doc" \
    "${HADOOP_HOME}/share/hadoop/tools" \
    "${HADOOP_HOME}/share/hadoop/client" \
    "${HADOOP_HOME}/lib/native" \
    "${HADOOP_HOME}/lib" \
    "${HADOOP_HOME}/include" \
    "${HADOOP_HOME}/sbin" \
    "${HADOOP_HOME}/licenses-binary" \
    "${HADOOP_HOME}/share/hadoop/common/jdiff" \
    "${HADOOP_HOME}/share/hadoop/common/sources" \
    "${HADOOP_HOME}/share/hadoop/hdfs/sources" \
    "${HADOOP_HOME}/share/hadoop/yarn/sources" \
    "${HADOOP_HOME}/share/hadoop/yarn/webapps" \
    "${HADOOP_HOME}/share/hadoop/yarn/test" \
    "${HADOOP_HOME}/share/hadoop/mapreduce/sources"

  after="$(du -sb "${HADOOP_HOME}" | awk '{print $1}')"
  saved=$(( (before - after) / 1024 / 1024 ))
  echo "[assemble] Lite profile: ~${saved} MB removed"
}

case "${DIST_PROFILE}" in
  lite|windows-client) trim_lite ;;
  full) echo "[assemble] Full profile: untrimmed Apache release" ;;
  *)
    echo "[assemble] Error: unknown HADOOP_DIST_PROFILE: ${DIST_PROFILE} (lite|full)" >&2
    exit 1
    ;;
esac

bash "${DOCKER_DIR}/verify-cdarlint-bin.sh" "${HADOOP_HOME}/bin"

for req in \
  "${HADOOP_HOME}/libexec/hadoop-config.cmd" \
  "${HADOOP_HOME}/etc/hadoop/core-site.xml" \
  "${HADOOP_HOME}/share/hadoop/common/hadoop-common-${HADOOP_VERSION}.jar" \
  "${HADOOP_HOME}/bin/hadoop.cmd"; do
  [[ -e "${req}" ]] || {
    echo "[assemble] Error: incomplete layout, missing: ${req}" >&2
    exit 1
  }
done

if ! compgen -G "${HADOOP_HOME}/share/hadoop/hdfs/hadoop-hdfs-${HADOOP_VERSION}.jar" >/dev/null; then
  echo "[assemble] Warning: hdfs jar missing (limited hdfs classpath)" >&2
fi

size_human="$(du -sh "${HADOOP_HOME}" | awk '{print $1}')"
echo "[assemble] HADOOP_HOME: ${HADOOP_HOME}/ (${DIST_PROFILE}, ${size_human}, release + native overlay)"
