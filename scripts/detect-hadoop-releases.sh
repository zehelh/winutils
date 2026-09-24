#!/usr/bin/env bash
# Detect missing GitHub Releases for Apache Hadoop versions (native + full by default).
# Output: JSON array of build items, e.g. [{"version":"3.4.2","package_mode":"native"},...]
set -euo pipefail

MIN_VERSION="${MIN_VERSION:-3.4.0}"
PACKAGE_MODES="${PACKAGE_MODES:-native,full}"
APACHE_BASE="${APACHE_BASE:-https://downloads.apache.org/hadoop/common}"

version_gte() {
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | head -1)" == "$b" ]]
}

release_tag() {
  local ver="$1" mode="$2"
  if [[ "${mode}" == "native" ]]; then
    echo "hadoop-${ver}"
  else
    echo "hadoop-${ver}-${mode}"
  fi
}

fetch_apache_versions() {
  curl -fsSL "${APACHE_BASE}/" \
    | grep -oE 'hadoop-[0-9]+\.[0-9]+\.[0-9]+' \
    | sed 's/hadoop-//' \
    | sort -V -u
}

tarball_exists() {
  local ver="$1"
  curl -fsI "${APACHE_BASE}/hadoop-${ver}/hadoop-${ver}.tar.gz" | head -1 | grep -q '200'
}

release_exists() {
  local tag="$1"
  gh release view "${tag}" >/dev/null 2>&1
}

mapfile -t modes < <(echo "${PACKAGE_MODES}" | tr ',' '\n' | sed '/^$/d')
mapfile -t apache_versions < <(fetch_apache_versions)

pending_versions=()
for ver in "${apache_versions[@]}"; do
  [[ "${ver}" =~ [Rr][Cc]|[Aa]lpha|[Bb]eta ]] && continue
  version_gte "${ver}" "${MIN_VERSION}" || continue
  tarball_exists "${ver}" || continue

  missing=0
  for mode in "${modes[@]}"; do
    tag="$(release_tag "${ver}" "${mode}")"
    release_exists "${tag}" || missing=1
  done
  [[ "${missing}" -eq 1 ]] && pending_versions+=("${ver}")
done

if [[ "${#pending_versions[@]}" -eq 0 ]]; then
  echo '[]'
  exit 0
fi

pending_items=()
for ver in "${pending_versions[@]}"; do
  for mode in "${modes[@]}"; do
    tag="$(release_tag "${ver}" "${mode}")"
    release_exists "${tag}" && continue
    pending_items+=("{\"version\":\"${ver}\",\"package_mode\":\"${mode}\"}")
  done
done

json='['
first=1
for item in "${pending_items[@]}"; do
  [[ "${first}" -eq 1 ]] || json+=','
  json+="${item}"
  first=0
done
json+=']'
echo "${json}"
