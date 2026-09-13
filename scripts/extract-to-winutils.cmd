@ECHO OFF
@REM Copy built Hadoop bin artifacts into hadoop-VERSION\bin in this repository.
@REM
@REM Usage:
@REM   scripts\extract-to-winutils.cmd native [HADOOP_SRC_DIR]
@REM   scripts\extract-to-winutils.cmd full   [HADOOP_SRC_DIR]
@REM
@REM   native - from build-native-only.cmd output
@REM   full   - from build-full-dist.cmd output (complete cdarlint-style folder)

SETLOCAL EnableDelayedExpansion

SET MODE=%~1
IF "%MODE%"=="" SET MODE=native

IF "%~2"=="" (
  SET HADOOP_SRC=%CD%\hadoop-src
) ELSE (
  SET HADOOP_SRC=%~2
)

IF NOT DEFINED HADOOP_VERSION SET HADOOP_VERSION=3.4.1

SET REPO_ROOT=%~dp0..
SET DEST=%REPO_ROOT%\hadoop-%HADOOP_VERSION%\bin

IF /I "%MODE%"=="native" (
  SET SRC=%HADOOP_SRC%\hadoop-common-project\hadoop-common\target\bin
) ELSE IF /I "%MODE%"=="full" (
  SET SRC=%HADOOP_SRC%\hadoop-dist\target\hadoop-%HADOOP_VERSION%\bin
) ELSE (
  ECHO [extract] ERROR: mode must be 'native' or 'full', got: %MODE%
  EXIT /B 1
)

IF NOT EXIST "%SRC%\winutils.exe" (
  ECHO [extract] ERROR: winutils.exe not found in %SRC%
  ECHO Build first with scripts\build-native-only.cmd or scripts\build-full-dist.cmd
  EXIT /B 1
)

IF NOT EXIST "%DEST%" mkdir "%DEST%"

ECHO [extract] Copying from %SRC% to %DEST% ...
xcopy /Y /I "%SRC%\*" "%DEST%\" >nul

@REM Remove debug symbols from distribution (cdarlint/steveloughran convention).
IF EXIST "%DEST%\*.pdb" del /Q "%DEST%\*.pdb"

ECHO [extract] Done. Contents of hadoop-%HADOOP_VERSION%\bin:
dir /B "%DEST%"

ENDLOCAL
EXIT /B 0
