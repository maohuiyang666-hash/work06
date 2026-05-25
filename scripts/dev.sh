#!/bin/bash
# ============================================================
# dvadmin3 统一开发启动脚本
# 用法:
#   ./scripts/dev.sh              # 同时启动前后端
#   ./scripts/dev.sh frontend      # 仅启动前端
#   ./scripts/dev.sh backend       # 仅启动后端
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

check_backend_env() {
    if [ ! -f "$PROJECT_ROOT/backend/conf/env.py" ]; then
        log_error "backend/conf/env.py 不存在！"
        log_info "请从 backend/conf/env.example.py 复制并修改配置:"
        log_info "  cp backend/conf/env.example.py backend/conf/env.py"
        exit 1
    fi
    log_info "backend/conf/env.py 已存在"
}

start_frontend() {
    log_info "启动前端开发服务器..."
    cd "$PROJECT_ROOT/web"
    npm run dev
}

start_backend() {
    log_info "启动后端开发服务器..."
    cd "$PROJECT_ROOT/backend"

    # 检查数据库迁移是否已执行
    log_info "检查数据库迁移状态..."
    python manage.py migrate --check 2>/dev/null || {
        log_warn "存在未执行的数据库迁移，正在执行 migrate..."
        python manage.py migrate
    }

    log_info "启动 Django 开发服务器 (manage.py runserver)..."
    python manage.py runserver 0.0.0.0:8000
}

case "${1:-all}" in
    frontend)
        start_frontend
        ;;
    backend)
        check_backend_env
        start_backend
        ;;
    all|*)
        check_backend_env
        log_info "=============================="
        log_info "  dvadmin3 开发环境启动"
        log_info "  前端: http://localhost:8080"
        log_info "  后端: http://localhost:8000"
        log_info "  接口文档: http://localhost:8000/swagger/"
        log_info "=============================="

        # 后台启动后端，前台启动前端
        cd "$PROJECT_ROOT/backend"
        python manage.py migrate --check 2>/dev/null || python manage.py migrate
        python manage.py runserver 0.0.0.0:8000 &
        BACKEND_PID=$!
        log_info "后端 PID: $BACKEND_PID"

        cd "$PROJECT_ROOT/web"
        npm run dev &
        FRONTEND_PID=$!

        # 捕获退出信号，清理子进程
        cleanup() {
            log_info "正在停止服务..."
            kill $BACKEND_PID 2>/dev/null
            kill $FRONTEND_PID 2>/dev/null
            log_info "已停止"
        }
        trap cleanup EXIT INT TERM
        wait
        ;;
esac