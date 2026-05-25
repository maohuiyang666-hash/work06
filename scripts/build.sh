#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-web}"

run_standard_web_build() {
  cd "$ROOT_DIR/web"
  npm run build
}

run_embedded_web_build() {
  cd "$ROOT_DIR/web"
  npm run build:local
}

usage() {
  echo "用法: ./scripts/build.sh [web|embedded-web]"
}

case "$MODE" in
  web)
    run_standard_web_build
    ;;
  embedded-web)
    run_embedded_web_build
    ;;
  *)
    usage
    exit 1
    ;;
esac
