#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-all}"
BACKEND_PORT="${BACKEND_PORT:-8000}"

run_web() {
  cd "$ROOT_DIR/web"
  npm run dev
}

run_backend() {
  if [[ ! -f "$ROOT_DIR/backend/conf/env.py" ]]; then
    echo "缺少 backend/conf/env.py，请先基于 backend/conf/env.example.py 准备后端配置"
    exit 1
  fi
  cd "$ROOT_DIR/backend"
  python3 -m uvicorn application.asgi:application --reload --host 0.0.0.0 --port "$BACKEND_PORT"
}

usage() {
  echo "用法: ./scripts/dev.sh [web|backend|all]"
}

case "$MODE" in
  web)
    run_web
    ;;
  backend)
    run_backend
    ;;
  all)
    cleanup() {
      if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT INT TERM
    run_backend &
    BACKEND_PID=$!
    sleep 2
    run_web
    ;;
  *)
    usage
    exit 1
    ;;
esac
