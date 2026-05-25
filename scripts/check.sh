#!/bin/bash
# 发布前检查脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web"
BACKEND_DIR="$PROJECT_ROOT/backend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "========================================="
echo "  Django-Vue3-Admin - 发布前检查"
echo "========================================="
echo -e "${NC}"

check_passed=0
check_failed=0
check_warnings=0

print_result() {
    local status=$1
    local message=$2
    local details=$3

    if [ "$status" = "pass" ]; then
        echo -e "  [${GREEN}✓${NC}] ${message}"
        ((check_passed++))
    elif [ "$status" = "warn" ]; then
        echo -e "  [${YELLOW}!${NC}] ${message}"
        if [ -n "$details" ]; then
            echo -e "      ${YELLOW}${details}${NC}"
        fi
        ((check_warnings++))
    else
        echo -e "  [${RED}✗${NC}] ${message}"
        if [ -n "$details" ]; then
            echo -e "      ${RED}${details}${NC}"
        fi
        ((check_failed++))
    fi
}

echo ""
echo "1. 检查前端配置..."
cd "$WEB_DIR"

if [ -f ".env.production" ]; then
    print_result "pass" "前端生产环境配置文件存在"
    api_url=$(grep '^VITE_API_URL=' .env.production | cut -d'=' -f2 | tr -d "'\" ")
    if [ -n "$api_url" ]; then
        print_result "pass" "VITE_API_URL 已配置: $api_url"
    else
        print_result "warn" "VITE_API_URL 可能未正确配置"
    fi
else
    print_result "fail" "前端生产环境配置文件不存在" ".env.production"
fi

echo ""
echo "2. 检查后端配置..."
cd "$BACKEND_DIR"

if [ -f "conf/env.py" ]; then
    print_result "pass" "后端配置文件存在"
    # 检查关键配置
    if grep -q "SECRET_KEY" "application/settings.py"; then
        print_result "pass" "SECRET_KEY 已配置"
    else
        print_result "warn" "请检查 SECRET_KEY 配置"
    fi

    if grep -q "DEBUG" "conf/env.py"; then
        debug_val=$(grep '^DEBUG' "conf/env.py" | cut -d'=' -f2 | tr -d ' ' | tr -d '#')
        if [ "$debug_val" = "True" ] || [ "$debug_val" = "true" ]; then
            print_result "warn" "DEBUG 模式在生产环境应设置为 False"
        else
            print_result "pass" "DEBUG 模式已禁用"
        fi
    fi
else
    print_result "fail" "后端配置文件不存在" "请复制 conf/env.example.py 为 conf/env.py"
fi

echo ""
echo "3. 检查后端依赖..."
cd "$BACKEND_DIR"
if [ -f "requirements.txt" ]; then
    print_result "pass" "requirements.txt 存在"
    # 尝试检查 Django 是否可导入（不实际运行）
    if python3 -c "import django" 2>/dev/null; then
        print_result "pass" "Python 依赖已安装"
    else
        print_result "warn" "Python 依赖可能未完整安装"
    fi
else
    print_result "fail" "requirements.txt 不存在"
fi

echo ""
echo "4. 运行 Django 系统检查..."
cd "$BACKEND_DIR"
if [ -f "manage.py" ]; then
    if python3 manage.py check --settings=application.settings 2>&1 | grep -q "System check identified no issues"; then
        print_result "pass" "Django 系统检查通过"
    else
        check_output=$(python3 manage.py check --settings=application.settings 2>&1 || true)
        print_result "warn" "Django 系统检查发现问题" "$check_output"
    fi
else
    print_result "fail" "manage.py 不存在"
fi

echo ""
echo "5. 检查前端构建能力..."
cd "$WEB_DIR"
if [ -f "package.json" ]; then
    print_result "pass" "package.json 存在"
    if [ -d "node_modules" ]; then
        print_result "pass" "node_modules 存在"
    else
        print_result "warn" "node_modules 不存在，构建前需要安装依赖"
    fi

    if grep -q '"build":' "package.json"; then
        print_result "pass" "build 脚本已配置"
    else
        print_result "fail" "build 脚本未配置"
    fi
else
    print_result "fail" "package.json 不存在"
fi

echo ""
echo "6. 检查前后端地址配置匹配..."
cd "$WEB_DIR"
if [ -f ".env.production" ] && [ -f "$BACKEND_DIR/conf/env.py" ]; then
    frontend_api=$(grep '^VITE_API_URL=' .env.production | cut -d'=' -f2 | tr -d "'\" ")
    backend_debug=$(grep '^DEBUG' "$BACKEND_DIR/conf/env.py" | cut -d'=' -f2 | tr -d ' ' | tr -d '#')

    if [ "$frontend_api" = "/api" ]; then
        print_result "pass" "前端 API 地址配置适合 nginx 代理模式"
    else
        print_result "warn" "请确认前端 API 地址与后端部署方式匹配"
    fi
fi

echo ""
echo "========================================="
echo "  检查结果汇总"
echo "========================================="
echo -e "  通过: ${GREEN}${check_passed}${NC}"
echo -e "  警告: ${YELLOW}${check_warnings}${NC}"
echo -e "  失败: ${RED}${check_failed}${NC}"
echo "========================================="

if [ $check_failed -gt 0 ]; then
    echo ""
    echo -e "${RED}存在必须修复的问题，无法继续发布${NC}"
    exit 1
elif [ $check_warnings -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}存在警告，请评估后继续${NC}"
    exit 0
else
    echo ""
    echo -e "${GREEN}所有检查通过，可以安全发布！${NC}"
    exit 0
fi
