#!/usr/bin/env bash
set -euo pipefail
WINE=$(command -v wine64 || command -v wine)
SYSTEMROOT="${SYSTEMROOT:-$(find /opt/msvc -type d -name Windows 2>/dev/null | head -1)}"
[[ -n "${SYSTEMROOT}" ]] || { echo "SYSTEMROOT not found" >&2; exit 1; }
exec "$WINE" "${SYSTEMROOT}\\system32\\cmd.exe" "$@"
