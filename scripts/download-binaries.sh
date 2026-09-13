#!/usr/bin/env bash
# Download pre-built Hadoop 3.4.1 winutils from notepass/hadoop-native-win-libs
# (transparent CI builds) and install into hadoop-3.4.1/bin/.
#
# Use this as a quick fallback while your own GitHub Actions build runs.
#
# Usage:
#   ./scripts/download-binaries.sh [source]
#
# Sources:
#   notepass  - notepass/hadoop-native-win-libs release (default)
#   custom URL - direct zip URL as second argument

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
HADOOP_VERSION="${HADOOP_VERSION:-3.4.1}"
DEST="${REPO_ROOT}/hadoop-${HADOOP_VERSION}/bin"
SOURCE="${1:-notepass}"

mkdir -p "$DEST"

case "$SOURCE" in
  notepass)
    URL="https://github.com/notepass/hadoop-native-win-libs/releases/download/rel/release-${HADOOP_VERSION}/hadoop-win-utils.zip"
    ;;
  *)
    URL="$SOURCE"
    ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[download-binaries] Fetching ${URL} ..."
curl -fsSL "$URL" -o "$TMP/hadoop-win-utils.zip"

echo "[download-binaries] Extracting to ${DEST} ..."
unzip -o "$TMP/hadoop-win-utils.zip" -d "$TMP/extract"

# notepass zip contains a 'bin' subfolder
if [[ -d "$TMP/extract/bin" ]]; then
  cp -a "$TMP/extract/bin/"* "$DEST"/
else
  cp -a "$TMP/extract/"* "$DEST"/
fi

echo "[download-binaries] Done:"
ls -la "$DEST"
