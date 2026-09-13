@ECHO OFF
@REM Full Hadoop distribution build with all Windows bin scripts (hadoop.cmd, hdfs.cmd, etc.).
@REM Takes 1-2 hours. Produces complete hadoop-3.4.1\bin folder.
@REM
@REM Usage (x64 Native Tools Command Prompt):
@REM   call scripts\win-paths.cmd
@REM   scripts\build-full-dist.cmd [HADOOP_SRC_DIR]

SETLOCAL

IF "%~1"=="" (
  SET HADOOP_SRC=%CD%\hadoop-src
) ELSE (
  SET HADOOP_SRC=%~1
)

IF NOT EXIST "%HADOOP_SRC%\pom.xml" (
  ECHO [build-full-dist] ERROR: Hadoop source not found at %HADOOP_SRC%
  ECHO Run scripts\clone-hadoop.cmd first.
  EXIT /B 1
)

IF NOT DEFINED VCPKG_ROOT (
  ECHO [build-full-dist] ERROR: VCPKG_ROOT not set. Run scripts\win-paths.cmd first.
  EXIT /B 1
)

PUSHD "%HADOOP_SRC%"

ECHO [build-full-dist] Full dist build for %HADOOP_GIT_REF% (this takes a long time) ...

set classpath=
set PROTOBUF_HOME=%VCPKG_ROOT%\installed\x64-windows

mvn clean package -Dhttps.protocols=TLSv1.2 -DskipTests -DskipDocs -Pnative-win,dist ^
  -Drequire.openssl -Drequire.test.libhadoop ^
  -Dshell-executable=%GIT_HOME%\bin\bash.exe ^
  -Dtar ^
  -Dopenssl.prefix=%VCPKG_ROOT%\installed\x64-windows ^
  -Dcmake.prefix.path=%VCPKG_ROOT%\installed\x64-windows ^
  -Dwindows.cmake.toolchain.file=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake ^
  -Dwindows.cmake.build.type=RelWithDebInfo ^
  -Dwindows.build.hdfspp.dll=off ^
  -Dwindows.no.sasl=on ^
  -Duse.platformToolsetVersion=%PLATFORM_TOOLSET%

SET RC=%ERRORLEVEL%
POPD

IF %RC% NEQ 0 (
  ECHO [build-full-dist] ERROR: Maven build failed.
  EXIT /B %RC%
)

ECHO [build-full-dist] Output: %HADOOP_SRC%\hadoop-dist\target\hadoop-%HADOOP_VERSION%\bin
ENDLOCAL
EXIT /B 0
