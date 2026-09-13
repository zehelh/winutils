@ECHO OFF
@REM Clone Apache Hadoop source at the release tag for building winutils.
@REM
@REM Usage (after win-paths.cmd):
@REM   scripts\clone-hadoop.cmd [DEST_DIR]

SETLOCAL

IF NOT DEFINED HADOOP_GIT_REF (
  ECHO [clone-hadoop] ERROR: call scripts\win-paths.cmd first.
  EXIT /B 1
)

IF "%~1"=="" (
  SET DEST=%CD%\hadoop-src
) ELSE (
  SET DEST=%~1
)

IF EXIST "%DEST%\.git" (
  ECHO [clone-hadoop] Updating existing clone at %DEST% ...
  PUSHD "%DEST%"
  git fetch --depth 1 origin %HADOOP_GIT_REF%
  git checkout %HADOOP_GIT_REF%
  POPD
) ELSE (
  ECHO [clone-hadoop] Cloning %HADOOP_GIT_REF% into %DEST% ...
  git clone --depth 1 --branch %HADOOP_GIT_REF% https://github.com/apache/hadoop.git "%DEST%"
)

IF ERRORLEVEL 1 (
  ECHO [clone-hadoop] ERROR: git operation failed.
  EXIT /B 1
)

@REM Apply Windows SDK compatibility shim (GetFileInformationByName collision).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-win-compat-shim.ps1" -Workspace "%DEST%"

ECHO [clone-hadoop] Ready: %DEST%
ENDLOCAL
EXIT /B 0
