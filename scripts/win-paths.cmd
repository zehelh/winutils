@ECHO OFF
@REM Licensed to the Apache Software Foundation (ASF) under one or more
@REM contributor license agreements.  See the NOTICE file distributed with
@REM this work for additional information regarding copyright ownership.
@REM The ASF licenses this file to You under the Apache License, Version 2.0
@REM (the "License"); you may not use this file except in compliance with
@REM the License.  You may obtain a copy of the License at
@REM
@REM     http://www.apache.org/licenses/LICENSE-2.0
@REM
@REM Unless required by applicable law or agreed to in writing, software
@REM distributed under the License is distributed on an "AS IS" BASIS,
@REM WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@REM See the License for the specific language governing permissions and
@REM limitations under the License.
@REM
@REM win-paths.cmd - Environment setup for building Hadoop native Windows libs.
@REM Based on apache/hadoop dev-support/win-paths-eg.cmd (release-3.4.1).
@REM
@REM Usage (from "x64 Native Tools Command Prompt for VS 2019/2022"):
@REM   call scripts\win-paths.cmd
@REM
@REM Override any path below before calling this script, e.g.:
@REM   set VCPKG_ROOT=D:\tools\vcpkg
@REM   call scripts\win-paths.cmd

SETLOCAL EnableDelayedExpansion

@REM ---- Build bitness (64-bit required for Hadoop 3.x) ----
IF NOT DEFINED Platform SET Platform=x64
IF NOT DEFINED VCVARSPLAT SET VCVARSPLAT=amd64

@REM ---- Tool locations (adjust to your machine) ----
IF NOT DEFINED VCPKG_ROOT SET VCPKG_ROOT=C:\vcpkg
IF NOT DEFINED JAVA_HOME SET JAVA_HOME=C:\Java\jdk8
IF NOT DEFINED MAVEN_HOME SET MAVEN_HOME=C:\Maven\apache-maven-3.8.6
IF NOT DEFINED GIT_HOME SET GIT_HOME=C:\Program Files\Git
IF NOT DEFINED CMAKE_HOME SET CMAKE_HOME=C:\CMake\cmake-3.19.0-win64-x64

@REM Short Maven repo path avoids "command line too long" errors on Windows.
IF NOT DEFINED MAVEN_LOCAL_REPO SET MAVEN_LOCAL_REPO=C:\m2
IF NOT DEFINED MAVEN_OPTS SET MAVEN_OPTS=-Xmx2048M -Xss128M -Dmaven.repo.local=%MAVEN_LOCAL_REPO%

@REM Native dependencies via vcpkg
SET PROTOBUF_HOME=%VCPKG_ROOT%\installed\x64-windows
SET ZLIB_HOME=%VCPKG_ROOT%\installed\x64-windows

@REM Hadoop version tag to checkout when cloning source
IF NOT DEFINED HADOOP_VERSION SET HADOOP_VERSION=3.4.1
IF NOT DEFINED HADOOP_GIT_REF SET HADOOP_GIT_REF=rel/release-3.4.1

@REM Visual Studio toolset: v142 = VS2019, v143 = VS2022
IF NOT DEFINED PLATFORM_TOOLSET SET PLATFORM_TOOLSET=v142

@REM ---- PATH ----
SET PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%CMAKE_HOME%\bin;%VCPKG_ROOT%;%GIT_HOME%\bin;%GIT_HOME%\usr\bin;%PATH%

@REM ---- Visual Studio environment ----
SET VS_FOUND=0

@REM VS 2022 Build Tools / Community / Professional
FOR %%E IN (BuildTools Community Professional Enterprise) DO (
  IF EXIST "C:\Program Files\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvarsall.bat" (
    CALL "C:\Program Files\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvarsall.bat" %VCVARSPLAT%
    SET VS_FOUND=1
    IF "%PLATFORM_TOOLSET%"=="v142" SET PLATFORM_TOOLSET=v143
    GOTO :vs_done
  )
)

@REM VS 2019 Build Tools / Community / Professional
FOR %%E IN (BuildTools Community Professional Enterprise) DO (
  IF EXIST "C:\Program Files (x86)\Microsoft Visual Studio\2019\%%E\VC\Auxiliary\Build\vcvarsall.bat" (
    CALL "C:\Program Files (x86)\Microsoft Visual Studio\2019\%%E\VC\Auxiliary\Build\vcvarsall.bat" %VCVARSPLAT%
    SET VS_FOUND=1
    GOTO :vs_done
  )
)

:vs_done
IF "%VS_FOUND%"=="0" (
  ECHO [win-paths] ERROR: Visual Studio 2019 or 2022 with C++ tools not found.
  ECHO Install "Desktop development with C++" or run from "x64 Native Tools Command Prompt".
  EXIT /B 1
)

@REM Javadoc fails on some JDK setups without clearing classpath
SET classpath=

@REM Git long paths (required for Hadoop source tree)
git config --global core.longpaths true 2>nul

ECHO [win-paths] Environment ready:
ECHO   HADOOP_VERSION=%HADOOP_VERSION%
ECHO   HADOOP_GIT_REF=%HADOOP_GIT_REF%
ECHO   JAVA_HOME=%JAVA_HOME%
ECHO   VCPKG_ROOT=%VCPKG_ROOT%
ECHO   PROTOBUF_HOME=%PROTOBUF_HOME%
ECHO   PLATFORM_TOOLSET=%PLATFORM_TOOLSET%
ECHO   MAVEN_LOCAL_REPO=%MAVEN_LOCAL_REPO%

ENDLOCAL & (
  SET Platform=%Platform%
  SET VCVARSPLAT=%VCVARSPLAT%
  SET VCPKG_ROOT=%VCPKG_ROOT%
  SET JAVA_HOME=%JAVA_HOME%
  SET MAVEN_HOME=%MAVEN_HOME%
  SET GIT_HOME=%GIT_HOME%
  SET CMAKE_HOME=%CMAKE_HOME%
  SET MAVEN_LOCAL_REPO=%MAVEN_LOCAL_REPO%
  SET MAVEN_OPTS=%MAVEN_OPTS%
  SET PROTOBUF_HOME=%PROTOBUF_HOME%
  SET ZLIB_HOME=%ZLIB_HOME%
  SET HADOOP_VERSION=%HADOOP_VERSION%
  SET HADOOP_GIT_REF=%HADOOP_GIT_REF%
  SET PLATFORM_TOOLSET=%PLATFORM_TOOLSET%
  SET classpath=
  SET PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%CMAKE_HOME%\bin;%VCPKG_ROOT%;%GIT_HOME%\bin;%GIT_HOME%\usr\bin;%PATH%
)
