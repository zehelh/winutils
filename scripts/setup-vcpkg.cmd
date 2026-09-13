@ECHO OFF
@REM Install vcpkg and native dependencies required by Hadoop 3.4.1 on Windows.
@REM See apache/hadoop BUILDING.txt and dev-support/docker/Dockerfile_windows_10.
@REM
@REM Usage:
@REM   scripts\setup-vcpkg.cmd [VCPKG_ROOT]
@REM
@REM Default VCPKG_ROOT: C:\vcpkg

SETLOCAL EnableDelayedExpansion

IF "%~1"=="" (
  SET VCPKG_ROOT=C:\vcpkg
) ELSE (
  SET VCPKG_ROOT=%~1
)

@REM Pin commit used by Hadoop's official Windows Docker image.
SET VCPKG_COMMIT=7ffa425e1db8b0c3edf9c50f2f3a0f25a324541d

IF NOT EXIST "%VCPKG_ROOT%\.git" (
  ECHO [setup-vcpkg] Cloning vcpkg into %VCPKG_ROOT% ...
  git clone https://github.com/microsoft/vcpkg.git "%VCPKG_ROOT%"
  IF ERRORLEVEL 1 EXIT /B 1
)

PUSHD "%VCPKG_ROOT%"
git fetch --depth 1 origin %VCPKG_COMMIT%
git checkout %VCPKG_COMMIT%
IF NOT EXIST vcpkg.exe (
  ECHO [setup-vcpkg] Bootstrapping vcpkg ...
  call bootstrap-vcpkg.bat
  IF ERRORLEVEL 1 EXIT /B 1
)

ECHO [setup-vcpkg] Installing x64-windows packages (this may take a while) ...
vcpkg.exe install boost:x64-windows protobuf:x64-windows openssl:x64-windows zlib:x64-windows
SET RC=%ERRORLEVEL%
POPD

IF %RC% NEQ 0 (
  ECHO [setup-vcpkg] ERROR: vcpkg install failed.
  EXIT /B %RC%
)

ECHO [setup-vcpkg] Done. Set VCPKG_ROOT=%VCPKG_ROOT% before building.
ENDLOCAL
EXIT /B 0
