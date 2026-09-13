#!/usr/bin/env bash
# Wrapper msbuild : convertit les chemins Unix dans /p:... pour midl/cl sous Wine.
set -euo pipefail

WINE=$(command -v wine64 || command -v wine)

# Chemins Z:/.../ avec slash final : MSBuild exige un séparateur, sans backslash avant ".
to_msbuild_path() {
  local p="$1"
  if [[ "$p" != /* ]]; then
    echo "$p"
    return
  fi
  p="${p%/}"
  p=$("${WINE}" winepath -w "$p" 2>/dev/null | tr -d '\r')
  p="${p//\\//}"
  echo "${p}/"
}

winify_prop() {
  local a="$1"
  local prefix prop val key
  if [[ "$a" =~ ^(/[pP]:)([^=]+)=(.*)$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    prop="${BASH_REMATCH[2]}"
    val="${BASH_REMATCH[3]}"
    key="${prop,,}"
    case "$key" in
      outdir|intermediateoutputpath|intdir|out)
        if [[ "$val" == /* ]]; then
          val="$(to_msbuild_path "$val")"
        fi
        ;;
    esac
    echo "${prefix}${prop}=${val}"
  else
    echo "$a"
  fi
}

args=()
for a in "$@"; do
  args+=("$(winify_prop "$a")")
done

exec /opt/msvc/bin/x64/msbuild "${args[@]}"
