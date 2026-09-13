#!/usr/bin/env bash
# HADOOP_HOME complet : release binaire Apache + winutils.exe / hadoop.dll natifs.
set -euo pipefail

HADOOP_VERSION="${1:?HADOOP_VERSION requis}"
HADOOP_HOME="${2:?HADOOP_HOME requis}"
NATIVE_BIN="${3:?NATIVE_BIN (target/bin natif) requis}"
CACHE_DIR="${4:-/src/.cache/hadoop-releases}"

TARBALL="hadoop-${HADOOP_VERSION}.tar.gz"
TARBALL_PATH="${CACHE_DIR}/${TARBALL}"
PARENT_DIR="$(dirname "${HADOOP_HOME}")"

[[ -f "${NATIVE_BIN}/winutils.exe" ]] || {
  echo "[assemble] Erreur: winutils.exe absent (${NATIVE_BIN})" >&2
  exit 1
}
[[ -f "${NATIVE_BIN}/hadoop.dll" ]] || {
  echo "[assemble] Erreur: hadoop.dll absent (${NATIVE_BIN})" >&2
  exit 1
}

mkdir -p "${CACHE_DIR}"

download_tarball() {
  local bases=(
    "https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}"
    "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}"
  )
  local base url

  for base in "${bases[@]}"; do
    url="${base}/${TARBALL}"
    echo "[assemble] Telechargement ${url}"
    if curl -fsSL --retry 3 --retry-delay 2 -o "${TARBALL_PATH}.partial" "${url}"; then
      mv -f "${TARBALL_PATH}.partial" "${TARBALL_PATH}"
      if curl -fsSL --retry 2 -o "${TARBALL_PATH}.sha512" "${url}.sha512" 2>/dev/null; then
        local expected actual
        # Format Apache : SHA512 (fichier) = <hash>
        expected="$(sed -n 's/.*= //p' "${TARBALL_PATH}.sha512" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        actual="$(sha512sum "${TARBALL_PATH}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
        if [[ "${expected}" != "${actual}" ]]; then
          echo "[assemble] Erreur: SHA512 invalide pour ${TARBALL}" >&2
          rm -f "${TARBALL_PATH}"
          exit 1
        fi
        echo "[assemble] SHA512 OK"
      else
        echo "[assemble] Avertissement: pas de verification SHA512" >&2
      fi
      return 0
    fi
    rm -f "${TARBALL_PATH}.partial"
  done

  echo "[assemble] Erreur: impossible de telecharger hadoop-${HADOOP_VERSION}.tar.gz" >&2
  exit 1
}

if [[ ! -f "${TARBALL_PATH}" ]]; then
  download_tarball
else
  echo "[assemble] Cache tarball ${TARBALL_PATH}"
fi

rm -rf "${HADOOP_HOME}"
mkdir -p "${PARENT_DIR}"
tar -xzf "${TARBALL_PATH}" -C "${PARENT_DIR}"

[[ -d "${HADOOP_HOME}" ]] || {
  echo "[assemble] Erreur: ${HADOOP_HOME} absent apres extraction" >&2
  exit 1
}

echo "[assemble] Overlay binaires natifs dans bin/"
cp -f "${NATIVE_BIN}/winutils.exe" "${NATIVE_BIN}/hadoop.dll" "${HADOOP_HOME}/bin/"

for req in \
  "${HADOOP_HOME}/libexec/hadoop-config.cmd" \
  "${HADOOP_HOME}/etc/hadoop/core-site.xml" \
  "${HADOOP_HOME}/share/hadoop/common/hadoop-common-${HADOOP_VERSION}.jar" \
  "${HADOOP_HOME}/bin/hadoop.cmd" \
  "${HADOOP_HOME}/bin/winutils.exe" \
  "${HADOOP_HOME}/bin/hadoop.dll"; do
  [[ -e "${req}" ]] || {
    echo "[assemble] Erreur: layout incomplet, manquant: ${req}" >&2
    exit 1
  }
done

if ! compgen -G "${HADOOP_HOME}/share/hadoop/hdfs/hadoop-hdfs-${HADOOP_VERSION}.jar" >/dev/null; then
  echo "[assemble] Avertissement: jar hdfs absent (classpath hdfs limite)" >&2
fi

echo "[assemble] HADOOP_HOME: ${HADOOP_HOME}/ (release Apache + natif Wine)"
