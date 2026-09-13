#!/usr/bin/env bash
# Build winutils for Hadoop 3.4.1 from Linux (CachyOS, Arch, etc.).
#
# Hadoop native Windows libs MUST be compiled with MSVC on Windows.
# On Linux you cannot run the official Windows Docker image (requires Windows host).
# This script triggers GitHub Actions (windows-latest) or downloads a finished artifact.
#
# Usage:
#   ./scripts/build-from-linux.sh trigger [native|full]
#   ./scripts/build-from-linux.sh download [RUN_ID]
#   ./scripts/build-from-linux.sh status
#
# Requirements for 'trigger': gh CLI authenticated (gh auth login)
# Requirements for 'download': gh CLI or curl + GitHub token for private repos

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
HADOOP_VERSION="${HADOOP_VERSION:-3.4.1}"
DEST="${REPO_ROOT}/hadoop-${HADOOP_VERSION}/bin"
WORKFLOW="build-winutils.yml"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  trigger [native|full]   Trigger GitHub Actions build (default: full)
  download [RUN_ID]       Download artifact from latest or specific workflow run
  status                  Show recent workflow runs

Environment:
  HADOOP_VERSION          Target version (default: 3.4.1)
  GITHUB_REPO             Override repo (default: auto-detect from git remote)

Examples:
  ./scripts/build-from-linux.sh trigger full
  ./scripts/build-from-linux.sh download
  ./scripts/build-from-linux.sh download 123456789
EOF
}

detect_repo() {
  if [[ -n "${GITHUB_REPO:-}" ]]; then
    echo "$GITHUB_REPO"
    return
  fi
  local remote url
  remote=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  if [[ "$remote" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    echo "${BASH_REMATCH[1]%.git}"
  else
    echo ""
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: 'gh' CLI required. Install: sudo pacman -S github-cli" >&2
    exit 1
  fi
}

cmd_trigger() {
  require_gh
  local mode="${1:-full}"
  local repo
  repo=$(detect_repo)
  if [[ -z "$repo" ]]; then
    echo "ERROR: cannot detect GitHub repo. Set GITHUB_REPO=owner/repo" >&2
    exit 1
  fi

  echo "[build-from-linux] Triggering ${WORKFLOW} on ${repo} (mode=${mode}) ..."
  gh workflow run "$WORKFLOW" \
    --repo "$repo" \
    -f "hadoop_ref=rel/release-${HADOOP_VERSION}" \
    -f "build_mode=${mode}"

  echo "[build-from-linux] Workflow triggered. Watch progress:"
  echo "  gh run list --repo ${repo} --workflow ${WORKFLOW}"
  echo "  gh run watch --repo ${repo}"
  echo ""
  echo "When finished, download with:"
  echo "  ./scripts/build-from-linux.sh download"
}

cmd_status() {
  require_gh
  local repo
  repo=$(detect_repo)
  if [[ -z "$repo" ]]; then
    echo "ERROR: cannot detect GitHub repo. Set GITHUB_REPO=owner/repo" >&2
    exit 1
  fi
  gh run list --repo "$repo" --workflow "$WORKFLOW" --limit 10
}

cmd_download() {
  require_gh
  local run_id="${1:-}"
  local repo
  repo=$(detect_repo)
  if [[ -z "$repo" ]]; then
    echo "ERROR: cannot detect GitHub repo. Set GITHUB_REPO=owner/repo" >&2
    exit 1
  fi

  if [[ -z "$run_id" ]]; then
    run_id=$(gh run list --repo "$repo" --workflow "$WORKFLOW" --limit 1 --json databaseId,conclusion --jq '.[0] | select(.conclusion=="success") | .databaseId')
    if [[ -z "$run_id" ]]; then
      echo "ERROR: no successful run found. Check: gh run list --repo ${repo}" >&2
      exit 1
    fi
    echo "[build-from-linux] Using latest successful run: ${run_id}"
  fi

  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "[build-from-linux] Downloading artifact from run ${run_id} ..."
  gh run download "$run_id" \
    --repo "$repo" \
    --name "hadoop-${HADOOP_VERSION}-winutils" \
    --dir "$tmp"

  mkdir -p "$DEST"
  cp -a "$tmp"/* "$DEST"/
  echo "[build-from-linux] Installed to ${DEST}:"
  ls -la "$DEST"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    trigger) cmd_trigger "${1:-full}" ;;
    download) cmd_download "${1:-}" ;;
    status) cmd_status ;;
    -h|--help|help|"") usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
