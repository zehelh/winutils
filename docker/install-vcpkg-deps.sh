#!/usr/bin/env bash
set -euo pipefail

VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
OVERLAY_TRIPLETS="/docker/triplets"
MARKER="${VCPKG_ROOT}/installed/x64-windows/share/boost/vcpkg-cmake-wrapper.cmake"

if [[ -f "${MARKER}" ]] || [[ -d "${VCPKG_ROOT}/installed/x64-windows/include/boost" ]]; then
  exit 0
fi

export WINEDEBUG=-all
# shellcheck source=/dev/null
source /opt/msvc/bin/x64/msvcenv.sh
export PATH="/usr/local/bin:/opt/msvc/bin/x64:${PATH}"

bash /docker/patch-vcpkg.sh

export VCPKG_DEFAULT_TRIPLET=x64-windows

"${VCPKG_ROOT}/vcpkg" install \
  --overlay-triplets="${OVERLAY_TRIPLETS}" \
  boost:x64-windows \
  protobuf:x64-windows \
  openssl:x64-windows \
  zlib:x64-windows
