#!/usr/bin/env bash
# Assemble a complete hadoop-3.4.1/bin/ folder on Linux:
#   - Shell/cmd wrappers from official Apache Hadoop distribution
#   - Native libs (winutils.exe, hadoop.dll, ...) from notepass CI build
#
# Same end result as cdarlint/steveloughran repos until a local Windows build completes.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
HADOOP_VERSION="${HADOOP_VERSION:-3.4.1}"
DEST="${REPO_ROOT}/hadoop-${HADOOP_VERSION}/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HADOOP_URL="${HADOOP_URL:-https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz}"
NATIVE_URL="${NATIVE_URL:-https://github.com/notepass/hadoop-native-win-libs/releases/download/rel/release-${HADOOP_VERSION}/hadoop-win-utils.zip}"

mkdir -p "$DEST"

echo "[assemble] Downloading Hadoop ${HADOOP_VERSION} distribution ..."
curl -fsSL "$HADOOP_URL" -o "$TMP/hadoop.tar.gz"

echo "[assemble] Extracting bin scripts from distribution ..."
tar -xzf "$TMP/hadoop.tar.gz" -C "$TMP" "hadoop-${HADOOP_VERSION}/bin"
cp -a "$TMP/hadoop-${HADOOP_VERSION}/bin/"* "$DEST"/

echo "[assemble] Downloading native Windows libs (notepass CI) ..."
curl -fsSL "$NATIVE_URL" -o "$TMP/native.zip"
unzip -o "$TMP/native.zip" -d "$TMP/native" >/dev/null

if [[ -d "$TMP/native/bin" ]]; then
  cp -a "$TMP/native/bin/"* "$DEST"/
else
  cp -a "$TMP/native/"* "$DEST"/
fi

rm -f "$DEST/.gitkeep"

echo "[assemble] Complete bin/ contents:"
ls -la "$DEST"
