#!/bin/bash
# ============================================================
# 统一开发启动脚本
# 用法:
#   ./scripts/dev.sh          # 启动前后端
#   ./scripts/dev.sh backend  # 仅启动后端
#   ./scripts/dev.sh frontend # 仅启动前端
# ============================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/web"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --------------------------------------------------
# 后端启动前检查
# --------------------------------------------------
check_backend() {
    info "检查后端环境..."

    # 1. 检查 env.py 是否存在
    if [ ! -f "$BACKEND_DIR/conf/env.py" ]; then
        warn "未找到 backend/conf/env.py"
        echo ""
        echo "  请选择配置模式:"
        echo "  1) 最小模式 (SQLite, 无需 MySQL/Redis) - 复制 env.minimal.py"
        echo "  2) 完整模式 (MySQL + Redis) - 复制 env.example.py"
        echo ""
        read -r -p "请输入选择 [1/2, 默认1]: " choice
        choice="${choice:-1}"
        if [ "$choice" = "2" ]; then
            cp "$BACKEND_DIR/conf/env.example.py" "$BACKEND_DIR/conf/env.py"
            warn "已创建 env.py（完整模式），请修改数据库/Redis地址！"
        else
            cp "$BACKEND_DIR/conf/env.minimal.py" "$BACKEND_DIR/conf/env.py"
            info "已创建 env.py（最小模式 - SQLite），无需 MySQL/Redis"
        fi
    fi

    # 2. 检查 Python 虚拟环境
    if [ -z "$VIRTUAL_ENV" ]; then
        warn "未检测到 Python 虚拟环境，建议先激活 venv"
    fi

    # 3. 检查依赖是否安装
    if ! python3 -c "import django" 2>/dev/null; then
        error "Django 未安装，请先执行: pip install -r backend/requirements.txt"
        exit 1
    fi

    # 4. 检查数据库连通性（不阻断，仅警告）
    if python3 -c "
import sys
sys.path.insert(0, '$BACKEND_DIR')
from conf.env import DATABASE_HOST, DATABASE_PORT
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect((DATABASE_HOST, DATABASE_PORT))
    s.close()
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        info "数据库连接正常 ($(
            python3 -c "
import sys; sys.path.insert(0, '$BACKEND_DIR')
from conf.env import DATABASE_HOST, DATABASE_PORT
print(f'{DATABASE_HOST}:{DATABASE_PORT}')
" 2>/dev/null))"

        # 检查是否需要执行迁移
        cd "$BACKEND_DIR"
        if python3 manage.py showmigrations --list 2>/dev/null | grep -q '\[ \]'; then
            warn "检测到未执行的数据库迁移，是否执行? (y/n)"
            read -r -t 10 answer || answer="n"
            if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
                info "执行数据库迁移..."
                python3 manage.py makemigrations
                python3 manage.py migrate
            fi
        fi
    else
        warn "数据库不可达，后端将以最小模式启动（部分功能不可用）"
    fi

    # 5. 检查 Redis 连通性（可选依赖）
    if python3 -c "
import sys; sys.path.insert(0, '$BACKEND_DIR')
from conf.env import REDIS_HOST
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect((REDIS_HOST, 6379))
    s.close()
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        info "Redis 连接正常"
    else
        warn "Redis 不可达，以下功能将不可用: Celery异步任务、Redis缓存、WebSocket(生产模式)"
        warn "系统仍可启动（WebSocket 使用 InMemoryChannelLayer 降级）"
    fi

    info "后端环境检查完成"
}

# --------------------------------------------------
# 前端启动前检查
# --------------------------------------------------
check_frontend() {
    info "检查前端环境..."

    # 1. 检查 Node.js
    if ! command -v node &>/dev/null; then
        error "未安装 Node.js，请先安装 Node.js >= 16.0.0"
        exit 1
    fi

    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -lt 16 ]; then
        error "Node.js 版本过低 ($NODE_VERSION)，需要 >= 16.0.0"
        exit 1
    fi

    # 2. 检查依赖是否安装
    if [ ! -d "$FRONTEND_DIR/node_modules" ]; then
        warn "未检测到 node_modules，正在安装依赖..."
        cd "$FRONTEND_DIR"
        npm install
    fi

    # 3. 检查 .env 文件
    if [ ! -f "$FRONTEND_DIR/.env" ]; then
        error "未找到 web/.env 文件"
        exit 1
    fi

    # 4. 检查 VITE_API_URL 配置
    API_URL=$(grep '^VITE_API_URL' "$FRONTEND_DIR/.env.development" 2>/dev/null | cut -d= -f2 | tr -d ' '"'"'"' || echo "")
    if [ -n "$API_URL" ]; then
        info "前端 API 地址: $API_URL (development)"
    fi

    info "前端环境检查完成"
}

# --------------------------------------------------
# 启动后端
# --------------------------------------------------
start_backend() {
    check_backend
    cd "$BACKEND_DIR"
    info "启动后端服务 (uvicorn)..."
    info "访问地址: http://127.0.0.1:8000"
    info "Swagger文档: http://127.0.0.1:8000/swagger/"
    info "按 Ctrl+C 停止服务"
    echo ""
    # 开发模式使用 runserver 以支持自动重载
    python3 manage.py runserver 0.0.0.0:8000
}

# --------------------------------------------------
# 启动前端
# --------------------------------------------------
start_frontend() {
    check_frontend
    cd "$FRONTEND_DIR"
    info "启动前端开发服务器 (vite)..."
    info "访问地址: http://localhost:8080"
    info "按 Ctrl+C 停止服务"
    echo ""
    npm run dev
}

# --------------------------------------------------
# 主逻辑
# --------------------------------------------------
MODE="${1:-all}"

case "$MODE" in
    backend)
        start_backend
        ;;
    frontend)
        start_frontend
        ;;
    all)
        info "========================================="
        info "  DVAdmin3 统一开发启动"
        info "========================================="
        echo ""

        # 先检查两端环境
        check_backend
        check_frontend

        echo ""
        info "启动后端服务 (后台运行)..."
        cd "$BACKEND_DIR"
        python3 manage.py runserver 0.0.0.0:8000 &
        BACKEND_PID=$!
        info "后端 PID: $BACKEND_PID -> http://127.0.0.1:8000"

        # 等待后端启动
        sleep 3

        info "启动前端开发服务器..."
        cd "$FRONTEND_DIR"
        npm run dev &
        FRONTEND_PID=$!
        info "前端 PID: $FRONTEND_PID -> http://localhost:8080"

        echo ""
        info "========================================="
        info "  前后端均已启动"
        info "  后端: http://127.0.0.1:8000"
        info "  前端: http://localhost:8080"
        info "  Swagger: http://127.0.0.1:8000/swagger/"
        info "  按 Ctrl+C 停止所有服务"
        info "========================================="

        # 捕获退出信号，清理子进程
        cleanup() {
            echo ""
            info "正在停止服务..."
            kill $BACKEND_PID 2>/dev/null || true
            kill $FRONTEND_PID 2>/dev/null || true
            info "已停止所有服务"
            exit 0
        }
        trap cleanup SIGINT SIGTERM

        # 等待任意子进程退出
        wait
        ;;
    *)
        echo "用法: $0 [all|backend|frontend]"
        echo "  all      - 启动前后端（默认）"
        echo "  backend  - 仅启动后端"
        echo "  frontend - 仅启动前端"
        exit 1
        ;;
esac
