#!/usr/bin/env bash
# Patch vcpkg for MSVC compilation via Wine (toolset=msvc, not gcc/MinGW).
set -euo pipefail

VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
BM="${VCPKG_ROOT}/ports/boost-modular-build-helper/boost-modular-build.cmake"
UC="${VCPKG_ROOT}/ports/boost-modular-build-helper/user-config.jam"
MSVC_JAM="${VCPKG_ROOT}/installed/x64-windows/tools/boost-build/src/tools/msvc.jam"

patch_boost_modular_build() {
  [[ -f "${BM}" ]] || return 0
  grep -q "msvc-wine" "${BM}" && return 0

  sed -i '/configure_file(${_bm_DIR}\/user-config.jam ${CURRENT_BUILDTREES_DIR}\/${TARGET_TRIPLET}-dbg/i\
    if(VCPKG_CHAINLOAD_TOOLCHAIN_FILE MATCHES "msvc-wine")\
        set(VCPKG_PLATFORM_TOOLSET v143)\
    endif()' "${BM}"

  sed -i 's/if(VCPKG_PLATFORM_TOOLSET MATCHES "v14.")/if(VCPKG_CHAINLOAD_TOOLCHAIN_FILE MATCHES "msvc-wine" OR VCPKG_PLATFORM_TOOLSET MATCHES "v14.")/' "${BM}"

  sed -i '/list(APPEND _bm_OPTIONS toolset=msvc)/a\
    if(VCPKG_CHAINLOAD_TOOLCHAIN_FILE MATCHES "msvc-wine")\
        list(APPEND _bm_OPTIONS target-os=windows)\
    endif()' "${BM}"

  local inst="${VCPKG_ROOT}/installed/x64-windows/share/boost-build/boost-modular-build.cmake"
  [[ -f "${inst}" ]] && cp "${BM}" "${inst}"
}

patch_user_config() {
  [[ -f "${UC}" ]] || return 0
  grep -q "/opt/msvc/bin/x64/cl.exe" "${UC}" && return 0

  sed -i 's|using msvc : : cl.exe|using msvc : 14.2 : /opt/msvc/bin/x64/cl.exe|' "${UC}"

  local inst="${VCPKG_ROOT}/installed/x64-windows/share/boost-build/user-config.jam"
  [[ -f "${inst}" ]] && cp "${UC}" "${inst}"
}

patch_msvc_jam_call_batch() {
  [[ -f "${MSVC_JAM}" ]] || return 0
  grep -q "msvc-wine-call-batch" "${MSVC_JAM}" && return 0

  python3 - "${MSVC_JAM}" <<'PY'
import sys
path = sys.argv[1]
old = """else
{
    # On cygwin, we need to run both the batch script
    # and the following command in the same instance
    # of cmd.exe.
    local rule call-batch-script ( command )
    {
        return "cmd.exe /S /C call $(command) \\">nul\\" \\"&&\\" " ;
    }
}"""
new = """else
{
    # msvc-wine-call-batch: msvcenv.sh already sourced, no cmd.exe on Linux.
    local rule call-batch-script ( command )
    {
        return "" ;
    }
}"""
text = open(path, encoding="utf-8").read()
if old not in text:
    sys.exit(0)
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
}

patch_msvc_jam_autodetect() {
  [[ -f "${MSVC_JAM}" ]] || return 0
  grep -q "msvc-wine-skip-autodetect" "${MSVC_JAM}" && return 0

  python3 - "${MSVC_JAM}" <<'PY'
import sys
path = sys.argv[1]
old = """    # Check environment and default installation paths.
    for local i in $(.known-versions)
    {
        if ! $(i) in [ $(.versions).all ]
        {
            register-configuration $(i) : [ default-path $(i) ] ;
        }
    }"""
new = """    # msvc-wine-skip-autodetect
    if [ os.name ] in NT CYGWIN
    {
        # Check environment and default installation paths.
        for local i in $(.known-versions)
        {
            if ! $(i) in [ $(.versions).all ]
            {
                local p = [ default-path $(i) ] ;
                if $(p)
                {
                    register-configuration $(i) : $(p) ;
                }
            }
        }
    }"""
text = open(path, encoding="utf-8").read()
if old not in text:
    sys.exit(0)
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
}

# Re-apply boost-modular-build if target-os is missing (incremental patch).
if [[ -f "${BM}" ]] && grep -q "msvc-wine" "${BM}" && ! grep -q "target-os=windows" "${BM}"; then
  sed -i '/list(APPEND _bm_OPTIONS toolset=msvc)/a\
    if(VCPKG_CHAINLOAD_TOOLCHAIN_FILE MATCHES "msvc-wine")\
        list(APPEND _bm_OPTIONS target-os=windows)\
    endif()' "${BM}"
  inst="${VCPKG_ROOT}/installed/x64-windows/share/boost-build/boost-modular-build.cmake"
  [[ -f "${inst}" ]] && cp "${BM}" "${inst}"
fi

install_link_wrapper() {
  local link_dir="/opt/msvc/bin/x64"
  local wrapper="/docker/link-wine.sh"
  [[ -f "${wrapper}" ]] || wrapper="/usr/local/bin/link"
  [[ -f "${wrapper}" ]] || return 0
  [[ -f "${link_dir}/link" ]] || return 0
  if [[ ! -f "${link_dir}/link.real" ]]; then
    cp -a "${link_dir}/link" "${link_dir}/link.real"
  fi
  install -m755 "${wrapper}" "${link_dir}/link"
}

patch_boost_modular_build
patch_user_config
patch_msvc_jam_autodetect
patch_msvc_jam_call_batch
install_link_wrapper
