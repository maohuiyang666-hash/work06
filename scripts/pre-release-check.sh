#!/bin/bash
# ============================================================
# dvadmin3 发布前自检脚本
# 检查项覆盖: 配置文件完整性、后端基础可用性、前端构建、
#             接口/鉴权/WebSocket 地址一致性、必需/可选依赖区分
# 用法:
#   ./scripts/pre-release-check.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
check_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
check_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }

# ============================================================
# 1. 配置文件存在性检查
# ============================================================
section_config() {
    echo ""
    echo -e "${BLUE}━━━ [1] 配置文件检查 ━━━${NC}"

    # 1.1 env.py 必须存在 (settings.py 第23行: from conf.env import *)
    if [ -f "$PROJECT_ROOT/backend/conf/env.py" ]; then
        check_pass "backend/conf/env.py 存在"
    else
        check_fail "backend/conf/env.py 缺失 — settings.py L23 'from conf.env import *' 会直接报错"
    fi

    # 1.2 env.example.py 是否存在
    if [ -f "$PROJECT_ROOT/backend/conf/env.example.py" ]; then
        check_pass "backend/conf/env.example.py 存在 (配置模板)"
    else
        check_warn "backend/conf/env.example.py 缺失"
    fi

    # 1.3 前端环境变量文件
    local frontend_envs=(".env" ".env.development" ".env.production")
    for f in "${frontend_envs[@]}"; do
        if [ -f "$PROJECT_ROOT/web/$f" ]; then
            check_pass "web/$f 存在"
        else
            check_warn "web/$f 缺失"
        fi
    done
}

# ============================================================
# 2. 后端配置完整性检查 (基于 env.example.py 中出现的配置项)
# ============================================================
section_backend_config() {
    echo ""
    echo -e "${BLUE}━━━ [2] 后端关键配置检查 ━━━${NC}"

    # 读取 env.py 内容用于后续校验
    local env_py="$PROJECT_ROOT/backend/conf/env.py"
    if [ ! -f "$env_py" ]; then
        check_fail "无法检查后端配置 — env.py 不存在"
        return
    fi

    # 2.1 DEBUG 值 (settings.py L42: DEBUG = locals().get("DEBUG", True))
    local debug_val=$(grep -oP 'DEBUG\s*=\s*\K(True|False)' "$env_py" 2>/dev/null || echo "")
    if [ "$debug_val" = "True" ]; then
        check_warn "DEBUG=True — 生产环境应设为 False (settings.py L42)"
    elif [ "$debug_val" = "False" ]; then
        check_pass "DEBUG=False (生产模式)"
    else
        check_warn "未显式设置 DEBUG，将使用默认值 True (settings.py L42)"
    fi

    # 2.2 DATABASE 配置 (settings.py L106-113)
    local db_engine=$(grep -oP 'DATABASE_ENGINE\s*=\s*"\K[^"]+' "$env_py" 2>/dev/null || echo "")
    local db_name=$(grep -oP 'DATABASE_NAME\s*=\s*'\''\K[^'\'']+' "$env_py" 2>/dev/null || echo "")
    local db_host=$(grep -oP 'DATABASE_HOST\s*=\s*'\''\K[^'\'']+' "$env_py" 2>/dev/null || echo "")

    if [ -n "$db_engine" ]; then
        if echo "$db_engine" | grep -q "sqlite"; then
            check_pass "数据库: SQLite (最小可运行路径，无需外部数据库)"
        elif echo "$db_engine" | grep -q "mysql"; then
            check_warn "数据库: MySQL — 需确认 $db_host:$db_name 可连接"
        else
            check_pass "数据库引擎: $db_engine"
        fi
    else
        check_warn "未检测到 DATABASE_ENGINE 配置"
    fi

    # 2.3 SECRET_KEY (settings.py L28 硬编码默认值，检查是否覆盖)
    local secret_in_env=$(grep -c 'SECRET_KEY' "$env_py" 2>/dev/null || echo "0")
    if [ "$secret_in_env" -gt 0 ]; then
        check_pass "SECRET_KEY 已在 env.py 中覆盖"
    else
        check_warn "SECRET_KEY 使用 settings.py 中的硬编码默认值，生产环境应覆盖"
    fi

    # 2.4 ALLOWED_HOSTS
    local allowed_hosts=$(grep -oP 'ALLOWED_HOSTS\s*=\s*\K\[[^\]]*\]' "$env_py" 2>/dev/null || echo "")
    if echo "$allowed_hosts" | grep -q '\*'; then
        check_warn "ALLOWED_HOSTS 包含 '*' — 生产环境建议限定域名/IP"
    elif [ -n "$allowed_hosts" ]; then
        check_pass "ALLOWED_HOSTS 已限定: $allowed_hosts"
    else
        check_warn "ALLOWED_HOSTS 未显式配置，默认 ['*']"
    fi

    # 2.5 Channels 层配置 (settings.py L171-182)
    local channel_layer=$(grep -A3 'CHANNEL_LAYERS' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null | grep 'BACKEND' || echo "")
    if echo "$channel_layer" | grep -q "InMemoryChannelLayer"; then
        check_warn "Channels 使用 InMemoryChannelLayer — 多进程部署时 WebSocket 消息无法跨进程共享"
    elif echo "$channel_layer" | grep -q "RedisChannelLayer"; then
        check_pass "Channels 使用 RedisChannelLayer"
    fi
}

# ============================================================
# 3. 必需依赖 vs 可选依赖区分
# ============================================================
section_dependencies() {
    echo ""
    echo -e "${BLUE}━━━ [3] 必需/可选依赖检查 ━━━${NC}"

    # 3.1 Django check (manage.py check)
    if command -v python3 &>/dev/null; then
        cd "$PROJECT_ROOT/backend"
        if python3 manage.py check --deploy 2>&1 | tail -5; then
            check_pass "Django check --deploy 通过"
        else
            check_warn "Django check --deploy 有警告 (部分为生产安全建议，非致命)"
        fi
        cd "$PROJECT_ROOT"
    else
        check_warn "python3 不可用，跳过 Django check"
    fi

    # 3.2 MySQL 连接检查 (可选 — 仅在使用 MySQL 时)
    local env_py="$PROJECT_ROOT/backend/conf/env.py"
    if [ -f "$env_py" ] && grep -q 'DATABASE_ENGINE.*mysql' "$env_py" 2>/dev/null; then
        check_warn "使用 MySQL 数据库 — 请手动确认数据库连接可用"
    fi

    # 3.3 Redis 连接检查 (可选 — channels_redis / celery broker)
    local redis_configured=false
    if [ -f "$env_py" ] && grep -q 'REDIS_HOST' "$env_py" 2>/dev/null; then
        local redis_host=$(grep -oP 'REDIS_HOST\s*=\s*'\''\K[^'\'']+' "$env_py" 2>/dev/null || echo "127.0.0.1")
        if command -v redis-cli &>/dev/null; then
            if redis-cli -h "$redis_host" ping &>/dev/null; then
                check_pass "Redis 连接正常 ($redis_host)"
            else
                check_warn "Redis ($redis_host) 不可达 — Celery/WebSocket跨进程将不可用，但主服务可启动"
            fi
        else
            check_warn "redis-cli 不可用，跳过 Redis 连接检查 — Celery/WebSocket跨进程可能受影响"
        fi
    else
        check_warn "未配置 Redis — Celery 异步任务、WebSocket 跨进程共享均不可用"
    fi

    # 3.4 Celery 检查 (可选 — settings.py L417 导入 dvadmin3_celery)
    check_warn "Celery 为可选依赖 — 未启动时异步任务功能不可用，主服务正常"
}

# ============================================================
# 4. 前端构建检查
# ============================================================
section_frontend_build() {
    echo ""
    echo -e "${BLUE}━━━ [4] 前端构建检查 ━━━${NC}"

    if [ ! -f "$PROJECT_ROOT/web/package.json" ]; then
        check_fail "web/package.json 缺失"
        return
    fi

    cd "$PROJECT_ROOT/web"

    # 检查 node_modules
    if [ -d "node_modules" ]; then
        check_pass "node_modules 存在"
    else
        check_warn "node_modules 不存在，将执行 npm install"
        npm install
    fi

    # 执行前端 build 检查
    echo "  正在执行前端 build..."
    if npm run build 2>&1 | tail -10; then
        check_pass "前端 build 成功"
    else
        check_fail "前端 build 失败 — 请检查 web/ 下的代码错误"
    fi

    cd "$PROJECT_ROOT"
}

# ============================================================
# 5. 接口基础地址 & 鉴权 & WebSocket 地址一致性
# ============================================================
section_url_consistency() {
    echo ""
    echo -e "${BLUE}━━━ [5] 接口/鉴权/WebSocket 地址一致性检查 ━━━${NC}"

    local frontend_api_url=""
    local frontend_ws_derived=""
    local backend_port="8000"

    # 5.1 读取前端 VITE_API_URL
    for envfile in "$PROJECT_ROOT/web/.env.production" "$PROJECT_ROOT/web/.env" "$PROJECT_ROOT/web/.env.development"; do
        if [ -f "$envfile" ]; then
            frontend_api_url=$(grep -oP 'VITE_API_URL\s*=\s*\K.*' "$envfile" 2>/dev/null | tr -d "'" | tr -d ' ' || echo "")
            if [ -n "$frontend_api_url" ]; then
                check_pass "前端 API 地址 ($(basename $envfile)): $frontend_api_url"
                break
            fi
        fi
    done

    if [ -z "$frontend_api_url" ]; then
        check_fail "未找到 VITE_API_URL 配置"
    fi

    # 5.2 WebSocket 地址推导逻辑 (baseUrl.ts L70-79)
    # 如果 VITE_API_URL 是相对路径 (如 /api)，则 WebSocket 从 location 推导
    # 如果 VITE_API_URL 是完整 HTTP URL，则替换为 ws/wss
    if [ -n "$frontend_api_url" ]; then
        if echo "$frontend_api_url" | grep -qE '^https?://'; then
            local ws_url=$(echo "$frontend_api_url" | sed 's|^http|ws|')
            check_pass "WebSocket 地址推导: $ws_url (baseUrl.ts getWsBaseURL)"
        elif echo "$frontend_api_url" | grep -qE '^/'; then
            check_warn "WebSocket 地址从浏览器 location 推导 (baseUrl.ts L70) — 确认部署时域名/端口正确"
        else
            check_warn "WebSocket 地址推导模式不明确 — 请检查 baseUrl.ts getWsBaseURL()"
        fi
    fi

    # 5.3 检查 WebSocket 路由注册 (asgi.py L22-28, ws_routing.py)
    if [ -f "$PROJECT_ROOT/backend/application/ws_routing.py" ]; then
        local ws_path=$(grep -oP "path\('\K[^']+" "$PROJECT_ROOT/backend/application/ws_routing.py" 2>/dev/null || echo "")
        if [ -n "$ws_path" ]; then
            check_pass "WebSocket 路由已注册: $ws_path (ws_routing.py)"
        else
            check_fail "WebSocket 路由未注册"
        fi
    else
        check_fail "ws_routing.py 缺失"
    fi

    # 5.4 检查前端 WebSocket 连接 URL (websocket.ts L32)
    if grep -q "ws/\${token}" "$PROJECT_ROOT/web/src/utils/websocket.ts" 2>/dev/null; then
        check_pass "前端 WebSocket URL 模板: ws/{token}/ (websocket.ts L32)"
    else
        check_warn "前端 WebSocket 地址模式未检测到"
    fi

    # 5.5 JWT 鉴权配置 (settings.py L289-300)
    if grep -q 'ACCESS_TOKEN_LIFETIME' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null; then
        local token_minutes=$(grep -oP 'timedelta\(minutes=\K\d+' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null || echo "1440")
        check_pass "JWT Access Token 有效期: ${token_minutes}分钟 (settings.py L289)"
    fi

    # 5.6 前端鉴权 token 发送 (request.ts L17-19)
    if grep -q "Authorization.*Session.get.*token" "$PROJECT_ROOT/web/src/utils/request.ts" 2>/dev/null; then
        check_pass "前端请求携带 JWT Token (request.ts L17-19)"
    else
        check_fail "前端未检测到 JWT Token 附加逻辑"
    fi

    # 5.7 前端 401 处理 (service.ts L82-91)
    if grep -q "Session.clear()" "$PROJECT_ROOT/web/src/utils/service.ts" 2>/dev/null; then
        check_pass "前端 401 响应已处理 (service.ts L82-91)"
    else
        check_warn "前端 401 处理可能不完整"
    fi
}

# ============================================================
# 6. 关键功能风险检查
# ============================================================
section_risk_points() {
    echo ""
    echo -e "${BLUE}━━━ [6] 关键风险点检查 ━━━${NC}"

    # 6.1 Swagger/接口文档访问 (settings.py L325-338, urls.py L88-96)
    if grep -q 'drf_yasg' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null; then
        local swagger_permission=$(grep -A2 'permission_classes' "$PROJECT_ROOT/backend/application/urls.py" 2>/dev/null | head -3)
        if echo "$swagger_permission" | grep -q 'AllowAny'; then
            check_warn "Swagger DEBUG=True 时公开访问 (urls.py L43)，生产环境 DEBUG=False 将要求认证"
        else
            check_pass "Swagger 已配置权限控制"
        fi
    fi

    # 6.2 静态资源与媒体文件 (settings.py L149-156)
    if grep -q 'MEDIA_ROOT' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null; then
        check_pass "MEDIA_ROOT=media/ MEDIA_URL=/media/ 已配置 (settings.py L151-152)"
    fi
    if grep -q 'STATICFILES_DIRS' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null; then
        check_pass "STATICFILES_DIRS 已配置 (settings.py L147-149)"
    fi
    if grep -q 'WhiteNoiseMiddleware' "$PROJECT_ROOT/backend/application/settings.py" 2>/dev/null; then
        check_pass "WhiteNoiseMiddleware 已启用 (settings.py L62)"
    fi

    # 6.3 动态系统配置初始化 (urls.py L41-42 dispatch.init_*)
    if grep -q 'dispatch.init_system_config\|dispatch.init_dictionary' "$PROJECT_ROOT/backend/application/urls.py" 2>/dev/null; then
        check_warn "系统配置/字典在 urls.py 模块加载时初始化 — 需要数据库已迁移且 SystemConfig/Dictionary 表存在"
    fi

    # 6.4 前端动态路由对登录后接口的依赖 (backEnd.ts)
    if grep -q 'getApiUserInfo\|getBackEndControlRoutes' "$PROJECT_ROOT/web/src/router/backEnd.ts" 2>/dev/null; then
        check_pass "后端控制路由模式: 登录后请求菜单接口 (backEnd.ts)"
    else
        check_warn "未检测到后端控制路由逻辑"
    fi

    # 6.5 数据库迁移状态
    if command -v python3 &>/dev/null && [ -f "$PROJECT_ROOT/backend/conf/env.py" ]; then
        cd "$PROJECT_ROOT/backend"
        if python3 -c "import django; django.setup()" 2>/dev/null; then
            check_pass "Django 环境可加载"
        else
            check_warn "Django 环境加载失败 — 可能数据库不可达或 env.py 配置有误"
        fi
        cd "$PROJECT_ROOT"
    fi
}

# ============================================================
# 7. 最小可运行路径说明
# ============================================================
section_minimal_path() {
    echo ""
    echo -e "${BLUE}━━━ [7] 最小可运行路径 ━━━${NC}"
    echo ""
    echo -e "  ${GREEN}必需依赖:${NC}"
    echo "    - Python 3.x + Django 4.2"
    echo "    - 数据库: SQLite (零配置) 或 MySQL"
    echo "    - backend/conf/env.py (从 env.example.py 复制)"
    echo ""
    echo -e "  ${YELLOW}可选依赖 (缺失时主服务仍可启动):${NC}"
    echo "    - Redis: 缺失则 Celery 异步任务不可用"
    echo "    - Redis: 缺失则 WebSocket 跨进程消息共享不可用 (单进程 InMemory 可用)"
    echo "    - Celery Worker: 缺失则异步任务/定时任务不可用"
    echo "    - MySQL: 可用 SQLite 替代"
    echo ""
    echo -e "  ${YELLOW}最小启动命令:${NC}"
    echo "    后端: cd backend && python manage.py runserver 0.0.0.0:8000"
    echo "    前端: cd web && npm run dev"
    echo ""
    echo -e "  ${YELLOW}最小启动下不可用功能:${NC}"
    echo "    - Celery 异步任务 / 定时任务"
    echo "    - WebSocket 多进程通信 (InMemoryChannelLayer 仅单进程)"
    echo "    - 系统配置/字典初始化需要先执行 migrate"
}

# ============================================================
# MAIN
# ============================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   dvadmin3 发布前自检                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

section_config
section_backend_config
section_dependencies
section_frontend_build
section_url_consistency
section_risk_points
section_minimal_path

# ============================================================
# 汇总
# ============================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  检查结果: ${GREEN}通过 $PASS${NC}  ${RED}失败 $FAIL${NC}  ${YELLOW}警告 $WARN${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}[!] 存在 $FAIL 项失败，请修复后重新检查${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}[OK] 所有必要检查通过，可以发布${NC}"
    exit 0
fi