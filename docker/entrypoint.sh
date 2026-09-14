#!/usr/bin/env bash
set -euo pipefail
git config --global --add safe.directory '*' 2>/dev/null || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
WINE=$(command -v wine64 || command -v wine)
wineserver -k >/dev/null 2>&1 || true
wineserver -p
"${WINE}" wineboot >/dev/null 2>&1
exec "$@"
