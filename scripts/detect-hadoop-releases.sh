#!/usr/bin/env bash
# Detect Apache Hadoop stable releases not yet published as GitHub Releases here.
# Output: JSON array on stdout, e.g. ["3.4.2","3.4.3"]
set -euo pipefail

MIN_VERSION="${MIN_VERSION:-3.4.0}"
MAX_BUILDS="${MAX_BUILDS:-1}"
APACHE_BASE="${APACHE_BASE:-https://downloads.apache.org/hadoop/common}"

version_gte() {
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | head -1)" == "$b" ]]
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
  local ver="$1"
  gh release view "hadoop-${ver}" >/dev/null 2>&1
}

mapfile -t apache_versions < <(fetch_apache_versions)

pending=()
for ver in "${apache_versions[@]}"; do
  [[ "${ver}" =~ [Rr][Cc]|[Aa]lpha|[Bb]eta ]] && continue
  version_gte "${ver}" "${MIN_VERSION}" || continue
  tarball_exists "${ver}" || continue
  release_exists "${ver}" && continue
  pending+=("${ver}")
done

if [[ "${#pending[@]}" -eq 0 ]]; then
  echo '[]'
  exit 0
fi

# Latest N versions only (avoid CI burst on first run).
start=$(( ${#pending[@]} - MAX_BUILDS ))
(( start < 0 )) && start=0
slice=("${pending[@]:start:MAX_BUILDS}")

json='['
first=1
for ver in "${slice[@]}"; do
  [[ "${first}" -eq 1 ]] || json+=','
  json+="\"${ver}\""
  first=0
done
json+=']'
echo "${json}"
