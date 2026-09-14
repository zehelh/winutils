#!/usr/bin/env bash
# Wrapper for GHA/self-hosted: always use Git Bash, never WSL.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Hadoop version required}"
GIT_BASH="${SHELL_EXECUTABLE:-${BASH:-bash}}"
export SHELL_EXECUTABLE="${GIT_BASH}"

if ! command -v msbuild.exe >/dev/null 2>&1; then
  echo "[build] msbuild missing - Setup Windows toolchain step failed" >&2
  exit 1
fi

msbuild -version | head -1
cd "${REPO_ROOT}"
"${GIT_BASH}" scripts/build-windows-native.sh "${VERSION}"
