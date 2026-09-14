#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.conf"
IMAGE_NAME="winutils-hadoop-wine-msvc"
REBUILD=0
SHELL_ONLY=0
DIST_FULL=0
HADOOP_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild-image) REBUILD=1; shift ;;
    --shell) SHELL_ONLY=1; shift ;;
    --full) DIST_FULL=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: ./build.sh [VERSION] [options]

  VERSION           Version Hadoop (defaut: 3.4.1). Voir versions.conf.
  --rebuild-image   Reconstruit l'image Docker
  --full            Release Apache complete (~1,7 Go), sans allègement
  --shell           Shell interactif dans le conteneur
  -h, --help        Affiche cette aide
EOF
      exit 0
      ;;
    -*)
      echo "Option inconnue: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${HADOOP_VERSION}" ]]; then
        HADOOP_VERSION="$1"
      else
        echo "Une seule version par invocation: ${HADOOP_VERSION}, $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

HADOOP_VERSION="${HADOOP_VERSION:-3.4.1}"

resolve_git_ref() {
  local ver="$1"
  local line key val
  if [[ -f "${VERSIONS_FILE}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// /}" ]] && continue
      key="${line%%=*}"
      val="${line#*=}"
      if [[ "${key}" == "${ver}" ]]; then
        echo "${val}"
        return 0
      fi
    done < "${VERSIONS_FILE}"
  fi
  echo "rel/release-${ver}"
}

HADOOP_GIT_REF="$(resolve_git_ref "${HADOOP_VERSION}")"

command -v docker >/dev/null 2>&1 || {
  echo "Docker introuvable." >&2
  exit 1
}

if [[ "$REBUILD" -eq 1 ]] || ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[build] Construction image ${IMAGE_NAME}"
  docker build ${REBUILD:+--no-cache} -t "${IMAGE_NAME}" \
    -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"
else
  echo "[build] Image ${IMAGE_NAME}"
fi

M2="${HOME}/.m2"
VCPKG_CACHE="${REPO_ROOT}/.cache/vcpkg-installed"
HADOOP_RELEASE_CACHE="${REPO_ROOT}/.cache/hadoop-releases"
mkdir -p "${M2}" "${VCPKG_CACHE}" "${HADOOP_RELEASE_CACHE}"
DEST="${REPO_ROOT}/hadoop-${HADOOP_VERSION}/bin"

RUN=(docker run --rm
  -v "${REPO_ROOT}:/src"
  -v "${REPO_ROOT}/docker:/docker:ro"
  -v "${REPO_ROOT}/docker/build-in-container.sh:/docker/build-in-container.sh:ro"
  -v "${REPO_ROOT}/docker/assemble-from-release.sh:/docker/assemble-from-release.sh:ro"
  -v "${REPO_ROOT}/docker/overlay-native-bin.sh:/docker/overlay-native-bin.sh:ro"
  -v "${REPO_ROOT}/docker/verify-cdarlint-bin.sh:/docker/verify-cdarlint-bin.sh:ro"
  -v "${REPO_ROOT}/docker/entrypoint.sh:/opt/entrypoint.sh:ro"
  -v "${REPO_ROOT}/docker/msbuild-wine.sh:/usr/local/bin/msbuild:ro"
  -v "${REPO_ROOT}/versions.conf:/src/versions.conf:ro"
  -v "${M2}:/root/.m2/repository"
  -v "${VCPKG_CACHE}:/opt/vcpkg/installed"
  -v "${HADOOP_RELEASE_CACHE}:/src/.cache/hadoop-releases"
  -e HOST_UID="$(id -u)"
  -e HOST_GID="$(id -g)"
  -e MAVEN_REPO=/root/.m2/repository
  -e HADOOP_VERSION="${HADOOP_VERSION}"
  -e HADOOP_GIT_REF="${HADOOP_GIT_REF}"
  -e HADOOP_DIST_PROFILE="$([[ "${DIST_FULL}" -eq 1 ]] && echo full || echo lite)"
)

fix_owner() {
  docker run --rm -v "${REPO_ROOT}:/src" "${IMAGE_NAME}" \
    chown -R "$(id -u):$(id -g)" "/src/hadoop-${HADOOP_VERSION}" /src/hadoop-src 2>/dev/null || true
}

HADOOP_HOME="${REPO_ROOT}/hadoop-${HADOOP_VERSION}"
trap fix_owner EXIT

if [[ "$SHELL_ONLY" -eq 1 ]]; then
  exec docker run -it "${RUN[@]}" "${IMAGE_NAME}" bash
fi

echo "[build] Hadoop ${HADOOP_VERSION} ref=${HADOOP_GIT_REF}"
if ! "${RUN[@]}" "${IMAGE_NAME}" bash /docker/build-in-container.sh; then
  echo "[build] Erreur: le conteneur a echoue (code de sortie non nul)." >&2
  exit 1
fi

if [[ -f "${DEST}/winutils.exe" && -f "${HADOOP_HOME}/libexec/hadoop-config.cmd" ]]; then
  echo "[build] Termine: ${HADOOP_HOME}/"
  ls -la "${DEST}"
else
  echo "[build] Erreur: layout incomplet (${HADOOP_HOME})" >&2
  exit 1
fi
