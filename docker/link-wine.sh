#!/usr/bin/env bash
# link.exe wrapper: convert Unix paths (including @file.rsp) for Wine/MSVC.
set -euo pipefail

# shellcheck source=/dev/null
source /opt/msvc/bin/x64/msvcenv.sh
WINE=$(command -v wine64 || command -v wine)

temps=()
cleanup() { rm -f "${temps[@]}" 2>/dev/null || true; }
trap cleanup EXIT

to_win_path() {
  local p="$1"
  p="${p#\"}"; p="${p%\"}"
  if [[ "$p" == /* ]]; then
    echo "z:${p}"
  else
    echo "$p"
  fi
}

winify_arg() {
  local a="$1"
  # MSVC options (/NOLOGO, /DLL, ...): do not convert.
  if [[ "$a" == /* ]] && [[ "$a" != //* ]] && [[ ! "$a" =~ ^/opt/ ]] && [[ ! "$a" =~ ^/tmp/ ]] && [[ ! "$a" =~ ^/src/ ]]; then
    echo "$a"
    return
  fi
  if [[ "$a" == /* ]]; then
    to_win_path "$a"
    return
  fi
  if [[ "$a" =~ ^(/[-A-Za-z]+)\"(/[^\"]+)\"$ ]]; then
    echo "${BASH_REMATCH[1]}\"$(to_win_path "/${BASH_REMATCH[2]#/}")\""
    return
  fi
  if [[ "$a" =~ ^(/[-A-Za-z]+)(/opt/.+)$ ]] || [[ "$a" =~ ^(/[-A-Za-z]+)(/tmp/.+)$ ]] || [[ "$a" =~ ^(/[-A-Za-z]+)(/src/.+)$ ]]; then
    echo "${BASH_REMATCH[1]}$(to_win_path "${BASH_REMATCH[2]}")"
    return
  fi
  echo "$a"
}

fix_rsp() {
  local rsp="$1"
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    local inner="$line"
    inner="${inner#\"}"; inner="${inner%\"}"
    if [[ "$inner" == /* ]]; then
      printf '"%s"\n' "$(to_win_path "$inner")"
    else
      echo "$line"
    fi
  done < "$rsp" > "$tmp"
  temps+=("$tmp")
  echo "$tmp"
}

args=()
for a in "$@"; do
  if [[ "$a" == @* ]]; then
    rsp="${a#@}"
    rsp="${rsp#\"}"; rsp="${rsp%\"}"
    fixed=$(fix_rsp "$rsp")
    args+=("@${fixed}")
  else
    args+=("$(winify_arg "$a")")
  fi
done

exec "${WINE}" "${BINDIR}/link.exe" "${args[@]}"
