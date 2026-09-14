FROM ubuntu:24.04

ARG MSVC_WINE_REF=514f8ea34842cd6d831804d0e9658d3a32870ae1
ARG CMAKE_VERSION=3.31.6
ARG VCPKG_COMMIT=7ffa425e1db8b0c3edf9c50f2f3a0f25a324541d

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl gpg wget python3 msitools git unzip zip tar build-essential \
    ninja-build pkg-config openjdk-8-jdk maven \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends winehq-staging \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
    | tar -xz -C /opt \
    && ln -sf "/opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake" /usr/local/bin/cmake

ARG WINE_MONO_VERSION=11.3.0
ENV WINEDEBUG=-all
ENV XDG_RUNTIME_DIR=/tmp/runtime-root
RUN mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root \
    && WINE=$(command -v wine64 || command -v wine) \
    && curl -fsSL -o /tmp/wine-mono.msi \
      "https://dl.winehq.org/wine/wine-mono/${WINE_MONO_VERSION}/wine-mono-${WINE_MONO_VERSION}-x86.msi" \
    && "${WINE}" wineboot --init \
    && "${WINE}" msiexec /i /tmp/wine-mono.msi /quiet \
    && rm -f /tmp/wine-mono.msi \
    && while pgrep wineserver > /dev/null; do sleep 1; done

WORKDIR /opt/msvc-wine
RUN git clone https://github.com/mstorsjo/msvc-wine.git . && git checkout "${MSVC_WINE_REF}"
RUN PYTHONUNBUFFERED=1 ./vsdownload.py --accept-license --architecture x64 x86 --dest /opt/msvc \
    && ./install.sh /opt/msvc

ENV PATH="/opt/msvc/bin/x64:${PATH}"

RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg \
    && cd /opt/vcpkg && git checkout "${VCPKG_COMMIT}" \
    && ./bootstrap-vcpkg.sh -disableMetrics

COPY msbuild-wine.sh /usr/local/bin/msbuild
COPY cmd-wine.sh /usr/local/bin/cmd
COPY link-wine.sh /usr/local/bin/link
COPY link-wine.sh /docker/link-wine.sh
COPY triplets/ /docker/triplets/
COPY toolchain-msvc-wine.cmake /docker/toolchain-msvc-wine.cmake
COPY install-vcpkg-deps.sh /docker/install-vcpkg-deps.sh
COPY patch-vcpkg.sh /docker/patch-vcpkg.sh
COPY setup-jdk-win32-headers.sh /docker/setup-jdk-win32-headers.sh
COPY setup-jdk-win64.sh /docker/setup-jdk-win64.sh
COPY patch-hadoop-jni-wine.sh /docker/patch-hadoop-jni-wine.sh
COPY build-hdfs-dll.sh /docker/build-hdfs-dll.sh
COPY assemble-from-release.sh /docker/assemble-from-release.sh
COPY overlay-native-bin.sh /docker/overlay-native-bin.sh
COPY verify-cdarlint-bin.sh /docker/verify-cdarlint-bin.sh
COPY jdk-win32/ /docker/jdk-win32/
COPY entrypoint.sh /opt/entrypoint.sh
COPY build-in-container.sh /opt/build-in-container.sh
RUN chmod +x /usr/local/bin/msbuild /usr/local/bin/cmd /usr/local/bin/link \
    /docker/install-vcpkg-deps.sh /docker/patch-vcpkg.sh /docker/setup-jdk-win32-headers.sh \
    /docker/setup-jdk-win64.sh /docker/patch-hadoop-jni-wine.sh /docker/build-hdfs-dll.sh \
    /docker/assemble-from-release.sh \
    /docker/overlay-native-bin.sh \
    /docker/verify-cdarlint-bin.sh \
    /docker/link-wine.sh /opt/entrypoint.sh /opt/build-in-container.sh \
    && bash /docker/setup-jdk-win32-headers.sh \
    && bash /docker/setup-jdk-win64.sh \
    && test -n "$(find /opt/msvc -name MSBuild.exe | head -1)"

WORKDIR /src
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/opt/build-in-container.sh"]
