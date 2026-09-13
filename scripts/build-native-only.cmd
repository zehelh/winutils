@ECHO OFF
@REM Fast build: winutils.exe, hadoop.dll and related native artifacts only.
@REM ~10 minutes. Does NOT produce hadoop.cmd / hdfs.cmd shell wrappers.
@REM
@REM Usage (x64 Native Tools Command Prompt):
@REM   call scripts\win-paths.cmd
@REM   scripts\build-native-only.cmd [HADOOP_SRC_DIR]

SETLOCAL

IF "%~1"=="" (
  SET HADOOP_SRC=%CD%\hadoop-src
) ELSE (
  SET HADOOP_SRC=%~1
)

IF NOT EXIST "%HADOOP_SRC%\pom.xml" (
  ECHO [build-native-only] ERROR: Hadoop source not found at %HADOOP_SRC%
  ECHO Run scripts\clone-hadoop.cmd first.
  EXIT /B 1
)

PUSHD "%HADOOP_SRC%"

ECHO [build-native-only] Building hadoop-common native libs for %HADOOP_GIT_REF% ...

mvn package -Pnative-win -DskipTests -Dmaven.javadoc.skip=true ^
  -pl :hadoop-common,:hadoop-maven-plugins

SET RC=%ERRORLEVEL%
POPD

IF %RC% NEQ 0 (
  ECHO [build-native-only] ERROR: Maven build failed.
  EXIT /B %RC%
)

ECHO [build-native-only] Output: %HADOOP_SRC%\hadoop-common-project\hadoop-common\target\bin
ENDLOCAL
EXIT /B 0
