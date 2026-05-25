#!/bin/bash
# ============================================================
# dvadmin3 发布前构建脚本
# 用法:
#   ./scripts/build.sh              # 默认: 前端构建到 dist/
#   ./scripts/build.sh local_prod   # 本地生产: 构建到 backend/templates/web/
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

MODE="${1:-production}"

case "$MODE" in
    local_prod|local)
        log_info "构建模式: local_prod (输出到 backend/templates/web/)"
        cd "$PROJECT_ROOT/web"
        npm run build:local
        log_info "构建完成，产物位于 backend/templates/web/"
        ;;
    production|prod|*)
        log_info "构建模式: production (输出到 web/dist/)"
        cd "$PROJECT_ROOT/web"
        npm run build
        log_info "构建完成，产物位于 web/dist/"
        ;;
esac