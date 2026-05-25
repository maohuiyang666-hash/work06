#!/bin/bash
# ============================================================
# 发布前构建脚本
# 用法:
#   ./scripts/build.sh          # 完整构建（前端+后端检查）
#   ./scripts/build.sh frontend # 仅构建前端
#   ./scripts/build.sh backend  # 仅后端构建检查
#   ./scripts/build.sh docker   # Docker镜像构建
# ============================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/web"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

ERRORS=0

# --------------------------------------------------
# 前端构建
# --------------------------------------------------
build_frontend() {
    step "========== 前端构建 =========="

    cd "$FRONTEND_DIR"

    # 1. 检查 Node.js
    if ! command -v node &>/dev/null; then
        error "未安装 Node.js"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    info "Node.js: $(node -v)"

    # 2. 安装依赖
    if [ ! -d "node_modules" ]; then
        info "安装前端依赖..."
        npm install
    fi

    # 3. 检查生产环境配置
    if [ ! -f ".env.production" ]; then
        error "缺少 web/.env.production 文件"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    PROD_API_URL=$(grep '^VITE_API_URL' .env.production | cut -d= -f2 | tr -d ' '"'"'"')
    info "生产环境 API 地址: $PROD_API_URL"

    # 4. 检查 API 地址是否为开发地址（常见错误）
    if echo "$PROD_API_URL" | grep -qE '127\.0\.0\.1|localhost'; then
        error "生产环境 VITE_API_URL 指向本地地址 ($PROD_API_URL)，发布后将无法访问后端！"
        error "请在 web/.env.production 中将 VITE_API_URL 设置为相对路径或线上地址"
        ERRORS=$((ERRORS + 1))
    fi

    # 5. 执行构建
    info "执行前端构建 (npm run build)..."
    if npm run build; then
        info "前端构建成功"
    else
        error "前端构建失败"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # 6. 检查构建产物
    DIST_DIR=$(grep 'VITE_DIST_PATH' .env.production 2>/dev/null | cut -d= -f2 | tr -d ' '"'"'"' || echo "dist")
    if [ -z "$DIST_DIR" ]; then
        DIST_DIR="dist"
    fi

    # local_prod 模式下构建产物直接输出到 backend/templates/web/
    if [ -f ".env.local_prod" ]; then
        LOCAL_PROD_DIST=$(grep '^VITE_DIST_PATH' .env.local_prod | cut -d= -f2 | tr -d ' '"'"'"')
        if [ -n "$LOCAL_PROD_DIST" ] && [ -d "$LOCAL_PROD_DIST" ]; then
            info "构建产物已输出到: $LOCAL_PROD_DIST"
            # 检查关键文件
            if [ -f "${LOCAL_PROD_DIST}index.html" ]; then
                info "index.html 存在"
            else
                error "构建产物中缺少 index.html"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    fi

    if [ -d "dist" ]; then
        info "dist 目录存在 ($(du -sh dist | cut -f1))"
    fi
}

# --------------------------------------------------
# 后端构建检查
# --------------------------------------------------
build_backend() {
    step "========== 后端构建检查 =========="

    cd "$BACKEND_DIR"

    # 1. 检查 env.py 是否存在
    if [ ! -f "conf/env.py" ]; then
        error "缺少 backend/conf/env.py，请从 env.example.py 复制并修改"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # 2. Django 系统检查
    info "执行 Django 系统检查 (manage.py check --deploy)..."
    if python3 manage.py check --deploy 2>&1; then
        info "Django 系统检查通过"
    else
        warn "Django --deploy 检查有警告（部分警告在开发阶段可忽略，生产环境需关注）"
    fi

    # 3. 检查 DEBUG 模式
    DEBUG_VALUE=$(python3 -c "
import sys; sys.path.insert(0, '.')
from conf.env import *
print(locals().get('DEBUG', True))
" 2>/dev/null || echo "True")

    if [ "$DEBUG_VALUE" = "True" ]; then
        warn "DEBUG=True，生产环境应设置为 False"
    else
        info "DEBUG=$DEBUG_VALUE"
    fi

    # 4. 检查 SECRET_KEY 是否为默认值
    if grep -q "django-insecure" "$BACKEND_DIR/application/settings.py"; then
        warn "SECRET_KEY 仍为默认的 django-insecure 值，生产环境必须更换"
    fi

    # 5. 收集静态文件（生产环境需要）
    info "检查静态文件..."
    if [ ! -d "static/rest_framework" ] || [ ! -d "static/drf-yasg" ]; then
        warn "静态文件不完整，建议执行: python3 manage.py collectstatic --noinput"
    else
        info "静态文件目录存在"
    fi

    # 6. 检查 media 目录
    if [ ! -d "media" ]; then
        mkdir -p media
        info "已创建 media 目录"
    fi

    # 7. 检查数据库迁移状态
    info "检查数据库迁移状态..."
    if python3 manage.py showmigrations --list 2>/dev/null | grep -q '\[ \]'; then
        warn "存在未执行的数据库迁移，发布前请执行: python3 manage.py migrate"
    else
        info "数据库迁移状态正常"
    fi

    # 8. 检查 ALLOWED_HOSTS
    ALLOWED_HOSTS_VALUE=$(python3 -c "
import sys; sys.path.insert(0, '.')
from conf.env import *
print(locals().get('ALLOWED_HOSTS', ['*']))
" 2>/dev/null || echo "['*']")

    if echo "$ALLOWED_HOSTS_VALUE" | grep -q '\*'; then
        warn "ALLOWED_HOSTS=['*']，生产环境应限制为具体域名"
    fi
}

# --------------------------------------------------
# Docker 构建
# --------------------------------------------------
build_docker() {
    step "========== Docker 镜像构建 =========="

    cd "$PROJECT_ROOT"

    # 1. 检查 .env 文件
    if [ ! -f ".env" ]; then
        error "缺少 .env 文件（Docker 部署需要 MYSQL_PASSWORD 和 REDIS_PASSWORD）"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # 2. 检查 docker-compose.yml
    if [ ! -f "docker-compose.yml" ]; then
        error "缺少 docker-compose.yml"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # 3. 检查 Dockerfile
    for dockerfile in docker_env/django/Dockerfile docker_env/web/Dockerfile docker_env/celery/Dockerfile; do
        if [ ! -f "$dockerfile" ]; then
            error "缺少 $dockerfile"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # 4. 检查 nginx 配置
    if [ ! -f "docker_env/nginx/my.conf" ]; then
        error "缺少 docker_env/nginx/my.conf"
        ERRORS=$((ERRORS + 1))
    fi

    info "Docker 配置检查完成"
    info "执行构建: docker-compose build"
    docker-compose build
}

# --------------------------------------------------
# 主逻辑
# --------------------------------------------------
MODE="${1:-all}"

case "$MODE" in
    frontend)
        build_frontend
        ;;
    backend)
        build_backend
        ;;
    docker)
        build_docker
        ;;
    all)
        build_frontend
        echo ""
        build_backend
        ;;
    *)
        echo "用法: $0 [all|frontend|backend|docker]"
        echo "  all      - 完整构建（前端+后端检查）"
        echo "  frontend - 仅构建前端"
        echo "  backend  - 仅后端构建检查"
        echo "  docker   - Docker镜像构建"
        exit 1
        ;;
esac

echo ""
if [ $ERRORS -gt 0 ]; then
    error "构建完成，但存在 $ERRORS 个错误，请修复后再发布！"
    exit 1
else
    info "构建检查全部通过，可以发布！"
fi
