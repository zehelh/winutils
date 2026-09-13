@ECHO OFF
@REM One-shot build pipeline for winutils (Windows).
@REM
@REM Usage (x64 Native Tools Command Prompt for VS 2019/2022):
@REM   scripts\build-all.cmd [native^|full]
@REM
@REM   native  - fast build, native DLLs/exe only (default)
@REM   full    - complete dist with all .cmd shell wrappers

SETLOCAL

SET MODE=%~1
IF "%MODE%"=="" SET MODE=native

SET SCRIPT_DIR=%~dp0
SET REPO_ROOT=%SCRIPT_DIR%..

PUSHD "%REPO_ROOT%"

ECHO ========================================
ECHO  winutils build for Hadoop 3.4.1
ECHO  mode: %MODE%
ECHO ========================================

call "%SCRIPT_DIR%win-paths.cmd"
IF ERRORLEVEL 1 GOTO :fail

call "%SCRIPT_DIR%clone-hadoop.cmd"
IF ERRORLEVEL 1 GOTO :fail

IF /I "%MODE%"=="full" (
  call "%SCRIPT_DIR%build-full-dist.cmd"
  IF ERRORLEVEL 1 GOTO :fail
  call "%SCRIPT_DIR%extract-to-winutils.cmd" full
) ELSE (
  call "%SCRIPT_DIR%build-native-only.cmd"
  IF ERRORLEVEL 1 GOTO :fail
  call "%SCRIPT_DIR%extract-to-winutils.cmd" native
)

IF ERRORLEVEL 1 GOTO :fail

ECHO.
ECHO [build-all] SUCCESS - binaries in hadoop-3.4.1\bin\
POPD
ENDLOCAL
EXIT /B 0

:fail
ECHO.
ECHO [build-all] FAILED - see messages above.
POPD
ENDLOCAL
EXIT /B 1
