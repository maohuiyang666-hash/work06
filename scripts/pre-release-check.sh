#!/bin/bash
# ============================================================
# 发布前自检脚本
# 基于仓库实际文件和配置进行发布前关键项检查
# 用法: ./scripts/pre-release-check.sh
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

PASS=0
FAIL=0
WARN_COUNT=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
step() { echo -e "\n${BLUE}[STEP]${NC} $*"; }

echo "=========================================================="
echo "  DVAdmin3 发布前自检"
echo "  项目根目录: $PROJECT_ROOT"
echo "=========================================================="

# ============================================================
# 1. 关键配置文件存在性检查
# ============================================================
step "1. 关键配置文件存在性检查"

# 1.1 后端 env.py
if [ -f "$BACKEND_DIR/conf/env.py" ]; then
    pass "backend/conf/env.py 存在"
else
    fail "backend/conf/env.py 不存在（需从 env.example.py 复制并修改）"
fi

# 1.2 前端环境配置
for envfile in .env .env.development .env.production; do
    if [ -f "$FRONTEND_DIR/$envfile" ]; then
        pass "web/$envfile 存在"
    else
        fail "web/$envfile 不存在"
    fi
done

# 1.3 Docker 部署配置
if [ -f "$PROJECT_ROOT/.env" ]; then
    pass ".env (Docker部署) 存在"
else
    warn ".env (Docker部署) 不存在（仅 Docker 部署时需要）"
fi

# 1.4 nginx 配置
if [ -f "$PROJECT_ROOT/docker_env/nginx/my.conf" ]; then
    pass "docker_env/nginx/my.conf 存在"
else
    fail "docker_env/nginx/my.conf 不存在"
fi

# ============================================================
# 2. 后端配置安全性检查（基于 settings.py 和 env.py）
# ============================================================
step "2. 后端配置安全性检查"

cd "$BACKEND_DIR"

# 2.1 DEBUG 模式
if [ -f "conf/env.py" ]; then
    if grep -q "DEBUG = True" conf/env.py 2>/dev/null; then
        warn "DEBUG=True（生产环境应设为 False）"
    elif grep -q "DEBUG = False" conf/env.py 2>/dev/null; then
        pass "DEBUG=False"
    else
        warn "未在 env.py 中显式设置 DEBUG（默认为 True）"
    fi
fi

# 2.2 SECRET_KEY
if grep -q "django-insecure" application/settings.py; then
    fail "SECRET_KEY 为默认的 django-insecure 值（生产环境必须更换）"
else
    pass "SECRET_KEY 已自定义"
fi

# 2.3 ALLOWED_HOSTS
if [ -f "conf/env.py" ]; then
    if grep -q 'ALLOWED_HOSTS = \["\*"\]' conf/env.py 2>/dev/null || \
       grep -q "ALLOWED_HOSTS = \['\*'\]" conf/env.py 2>/dev/null; then
        warn "ALLOWED_HOSTS=['*']（生产环境应限制为具体域名）"
    else
        pass "ALLOWED_HOSTS 已限制"
    fi
fi

# 2.4 数据库配置
if [ -f "conf/env.py" ]; then
    if grep -q "DATABASE_ENGINE.*sqlite3" conf/env.py 2>/dev/null; then
        warn "使用 SQLite 数据库（生产环境建议使用 MySQL）"
    elif grep -q "DATABASE_ENGINE.*mysql" conf/env.py 2>/dev/null; then
        pass "使用 MySQL 数据库"
    fi

    # 检查数据库密码是否为默认值
    if grep -q "DATABASE_PASSWORD = 'DVADMIN3'" conf/env.py 2>/dev/null; then
        fail "数据库密码为默认值 DVADMIN3（必须修改）"
    else
        pass "数据库密码已修改"
    fi
fi

# 2.5 Redis 密码
if [ -f "conf/env.py" ]; then
    if grep -q "REDIS_PASSWORD = 'DVADMIN3'" conf/env.py 2>/dev/null; then
        fail "Redis 密码为默认值 DVADMIN3（必须修改）"
    else
        pass "Redis 密码已修改"
    fi
fi

# 2.6 CORS 配置
if grep -q "CORS_ORIGIN_ALLOW_ALL = True" application/settings.py; then
    warn "CORS_ORIGIN_ALLOW_ALL=True（生产环境建议限制允许的域名）"
fi

# ============================================================
# 3. 前后端地址一致性检查
# ============================================================
step "3. 前后端地址一致性检查"

# 3.1 前端 API 地址检查
if [ -f "$FRONTEND_DIR/.env.production" ]; then
    PROD_API_URL=$(grep '^VITE_API_URL' "$FRONTEND_DIR/.env.production" | cut -d= -f2 | tr -d ' '"'"'"')

    if echo "$PROD_API_URL" | grep -qE '127\.0\.0\.1|localhost'; then
        fail "生产环境 VITE_API_URL 指向本地 ($PROD_API_URL)"
    elif [ "$PROD_API_URL" = "/api" ]; then
        pass "生产环境 VITE_API_URL=/api（nginx 代理模式）"
    elif [ -n "$PROD_API_URL" ]; then
        pass "生产环境 VITE_API_URL=$PROD_API_URL"
    else
        fail "生产环境 VITE_API_URL 为空"
    fi
fi

# 3.2 WebSocket 地址推导检查
if [ -f "$FRONTEND_DIR/.env.production" ]; then
    PROD_API_URL=$(grep '^VITE_API_URL' "$FRONTEND_DIR/.env.production" | cut -d= -f2 | tr -d ' '"'"'")
    if [ "$PROD_API_URL" = "/api" ]; then
        # getWsBaseURL() 会将 /api 开头的路径转为 ws://当前域名/api
        pass "WebSocket 地址将基于当前域名自动推导（与 nginx 代理一致）"
    elif echo "$PROD_API_URL" | grep -qE '^http'; then
        # getWsBaseURL() 会将 http 替换为 ws
        WS_URL=$(echo "$PROD_API_URL" | sed 's/http/ws/')
        info_msg="WebSocket 地址推导: $WS_URL"
        pass "$info_msg"
    fi
fi

# 3.3 开发环境 API 地址与后端端口一致性
if [ -f "$FRONTEND_DIR/.env.development" ]; then
    DEV_API_URL=$(grep '^VITE_API_URL' "$FRONTEND_DIR/.env.development" | cut -d= -f2 | tr -d ' '"'"'")
    if echo "$DEV_API_URL" | grep -q '8000'; then
        pass "开发环境 API 地址 ($DEV_API_URL) 与后端端口 8000 一致"
    else
        warn "开发环境 API 地址 ($DEV_API_URL) 可能与后端端口不匹配"
    fi
fi

# 3.4 nginx 代理与后端地址一致性
if [ -f "$PROJECT_ROOT/docker_env/nginx/my.conf" ]; then
    NGINX_PROXY=$(grep 'proxy_pass' "$PROJECT_ROOT/docker_env/nginx/my.conf" | head -1 | awk '{print $2}' | tr -d ';')
    if echo "$NGINX_PROXY" | grep -q '8000'; then
        pass "nginx 代理地址 ($NGINX_PROXY) 指向后端 8000 端口"
    else
        warn "nginx 代理地址 ($NGINX_PROXY) 未指向 8000 端口"
    fi
fi

# ============================================================
# 4. 前端构建检查
# ============================================================
step "4. 前端构建检查"

cd "$FRONTEND_DIR"

# 4.1 前端能否正常 build
if command -v node &>/dev/null; then
    if [ -d "node_modules" ]; then
        info "执行前端构建测试..."
        if npm run build 2>&1 | tail -1 | grep -qiE 'error|fail'; then
            fail "前端构建失败"
        else
            pass "前端构建成功"
        fi
    else
        warn "node_modules 不存在，跳过构建测试（请先 npm install）"
    fi
else
    warn "Node.js 未安装，跳过前端构建检查"
fi

# 4.2 检查前端鉴权处理
if [ -f "src/utils/service.ts" ]; then
    # 检查 401 处理是否存在
    if grep -q '401' src/utils/service.ts; then
        pass "前端 service.ts 包含 401 鉴权失效处理"
    else
        fail "前端 service.ts 缺少 401 鉴权失效处理"
    fi

    # 检查 JWT token 拼接方式
    if grep -q "JWT " src/utils/service.ts; then
        pass "前端使用 JWT 前缀（与后端 SIMPLE_JWT.AUTH_HEADER_TYPES 一致）"
    else
        warn "前端 JWT 前缀可能与后端不一致"
    fi
fi

# ============================================================
# 5. 后端基础可用性检查
# ============================================================
step "5. 后端基础可用性检查"

cd "$BACKEND_DIR"

# 5.1 Django check
if python3 manage.py check 2>&1 | grep -qiE 'error|SystemCheckError'; then
    fail "Django 系统检查未通过"
else
    pass "Django 系统检查通过"
fi

# 5.2 数据库迁移状态
if python3 manage.py showmigrations --list 2>/dev/null | grep -q '\[ \]'; then
    fail "存在未执行的数据库迁移"
else
    pass "数据库迁移状态正常"
fi

# 5.3 静态文件完整性
if [ -d "static/rest_framework" ] && [ -d "static/drf-yasg" ]; then
    pass "静态文件目录完整（rest_framework, drf-yasg）"
else
    warn "静态文件不完整，Swagger/接口文档可能无法访问"
fi

# 5.4 media 目录
if [ -d "media" ]; then
    pass "media 目录存在"
else
    warn "media 目录不存在（文件上传功能将不可用）"
fi

# 5.5 日志目录
if [ -d "logs" ]; then
    pass "logs 目录存在"
else
    warn "logs 目录不存在"
fi

# ============================================================
# 6. WebSocket 配置检查
# ============================================================
step "6. WebSocket 配置检查"

# 6.1 Channel Layers 配置
if grep -q 'InMemoryChannelLayer' application/settings.py; then
    warn "CHANNEL_LAYERS 使用 InMemoryChannelLayer（仅开发可用，生产环境应切换到 Redis）"
elif grep -q 'channels_redis' application/settings.py; then
    pass "CHANNEL_LAYERS 使用 Redis（生产推荐）"
fi

# 6.2 WebSocket 路由
if [ -f "application/ws_routing.py" ]; then
    pass "WebSocket 路由文件存在 (ws_routing.py)"
else
    fail "WebSocket 路由文件不存在"
fi

# 6.3 前端 WebSocket 连接
if [ -f "$FRONTEND_DIR/src/utils/websocket.ts" ]; then
    if grep -q 'getWsBaseURL' "$FRONTEND_DIR/src/utils/websocket.ts"; then
        pass "前端 WebSocket 使用 getWsBaseURL() 动态获取地址"
    else
        warn "前端 WebSocket 地址未使用动态获取"
    fi

    # 检查 token 传递
    if grep -q 'token' "$FRONTEND_DIR/src/utils/websocket.ts"; then
        pass "前端 WebSocket 连接携带 token"
    else
        fail "前端 WebSocket 连接未携带 token（鉴权将失败）"
    fi
fi

# ============================================================
# 7. Swagger / 接口文档检查
# ============================================================
step "7. Swagger / 接口文档检查"

# 7.1 drf-yasg 已安装
if grep -q 'drf_yasg' application/settings.py; then
    pass "drf_yasg 已注册到 INSTALLED_APPS"
else
    fail "drf_yasg 未注册"
fi

# 7.2 Swagger URL 配置
if grep -q 'swagger' application/urls.py; then
    pass "Swagger URL 已配置"
else
    warn "Swagger URL 未配置"
fi

# 7.3 生产环境 Swagger 权限
if grep -q 'permissions.AllowAny.*DEBUG' application/urls.py 2>/dev/null || \
   grep -q 'settings.DEBUG' application/urls.py 2>/dev/null; then
    pass "Swagger 权限与 DEBUG 状态关联"
else
    warn "Swagger 权限未与 DEBUG 关联，生产环境可能暴露接口文档"
fi

# ============================================================
# 8. 动态系统配置与路由初始化检查
# ============================================================
step "8. 动态系统配置与路由初始化检查"

# 8.1 系统配置初始化
if grep -q 'init_system_config' application/urls.py; then
    pass "系统配置初始化 (dispatch.init_system_config) 已在 urls.py 中调用"
else
    warn "系统配置初始化未在 urls.py 中调用"
fi

# 8.2 字典初始化
if grep -q 'init_dictionary' application/urls.py; then
    pass "字典初始化 (dispatch.init_dictionary) 已在 urls.py 中调用"
else
    warn "字典初始化未在 urls.py 中调用"
fi

# 8.3 前端动态路由
if [ -f "$FRONTEND_DIR/src/router/backEnd.ts" ]; then
    if grep -q 'getBackEndControlRoutes' "$FRONTEND_DIR/src/router/backEnd.ts"; then
        pass "前端动态路由从后端接口获取 (getBackEndControlRoutes)"
    else
        warn "前端动态路由获取方式异常"
    fi

    # 检查登录后路由初始化依赖
    if grep -q 'getApiUserInfo' "$FRONTEND_DIR/src/router/backEnd.ts"; then
        pass "动态路由初始化依赖用户信息接口 (getApiUserInfo)"
    fi

    if grep -q 'BtnPermissionStore' "$FRONTEND_DIR/src/router/backEnd.ts"; then
        pass "动态路由初始化获取按钮权限 (BtnPermissionStore)"
    fi

    if grep -q 'SystemConfigStore' "$FRONTEND_DIR/src/router/backEnd.ts"; then
        pass "动态路由初始化获取系统配置 (SystemConfigStore)"
    fi
fi

# ============================================================
# 9. 依赖完整性检查
# ============================================================
step "9. 依赖完整性检查"

# 9.1 后端 Python 依赖
if [ -f "requirements.txt" ]; then
    pass "requirements.txt 存在"
    # 检查关键依赖
    for pkg in Django djangorestframework channels uvicorn mysqlclient; do
        if grep -q "^${pkg}==" requirements.txt || grep -q "^${pkg}>" requirements.txt; then
            pass "关键依赖 $pkg 已在 requirements.txt 中声明"
        else
            warn "关键依赖 $pkg 未在 requirements.txt 中找到"
        fi
    done
fi

# 9.2 前端依赖
if [ -f "$FRONTEND_DIR/package.json" ]; then
    pass "package.json 存在"
fi

# ============================================================
# 10. 可选依赖与最小可运行路径
# ============================================================
step "10. 可选依赖与最小可运行路径"

# 10.1 Redis 可选性
if grep -q 'InMemoryChannelLayer' application/settings.py; then
    pass "Redis 为可选依赖（CHANNEL_LAYERS 已配置 InMemory 降级）"
    warn "  最小模式下不可用: Celery异步任务、Redis缓存、WebSocket跨进程通信"
    warn "  最小模式下可用: HTTP接口、JWT鉴权、登录、动态路由、Swagger文档"
else
    warn "Redis 为必需依赖（CHANNEL_LAYERS 使用 Redis，无 Redis 将无法启动）"
fi

# 10.2 Celery 可选性
if grep -q 'dvadmin3_celery' application/settings.py; then
    warn "Celery 插件已启用，但 Celery Worker 不启动不影响主服务运行"
    pass "Celery 为可选依赖（异步任务功能不可用，但主服务可启动）"
fi

# 10.3 MySQL 可选性
if [ -f "conf/env.py" ] && grep -q "sqlite3" conf/env.py 2>/dev/null; then
    pass "MySQL 为可选依赖（当前使用 SQLite）"
else
    warn "MySQL 为必需依赖（当前配置使用 MySQL，无 MySQL 将无法启动）"
    warn "  最小可运行路径: cp conf/env.minimal.py conf/env.py 可脱离 MySQL 运行"
fi

# ============================================================
# 汇总
# ============================================================
echo ""
echo "=========================================================="
echo "  自检结果汇总"
echo "=========================================================="
echo -e "  ${GREEN}通过: $PASS${NC}"
echo -e "  ${RED}失败: $FAIL${NC}"
echo -e "  ${YELLOW}警告: $WARN_COUNT${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}存在 $FAIL 个必须修复的问题，请修复后再发布！${NC}"
    exit 1
elif [ $WARN_COUNT -gt 0 ]; then
    echo -e "${YELLOW}存在 $WARN_COUNT 个警告，建议关注但不阻断发布。${NC}"
    exit 0
else
    echo -e "${GREEN}所有检查项通过，可以发布！${NC}"
    exit 0
fi
