# Triplet x64-windows pour compilation MSVC via Wine (hote Linux).
# Pas de VCPKG_CMAKE_SYSTEM_NAME : evite le chemin cross-compile MinGW de boost-build.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "/docker/toolchain-msvc-wine.cmake")
