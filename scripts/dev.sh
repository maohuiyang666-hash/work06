#!/bin/bash
# 前端开发启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web"

echo "========================================="
echo "  Django-Vue3-Admin - 前端开发启动"
echo "========================================="
echo ""

# 检查是否在正确的目录
if [ ! -d "$WEB_DIR" ]; then
    echo "错误: 找不到 web 目录"
    exit 1
fi

cd "$WEB_DIR"

# 检查 node_modules 是否存在
if [ ! -d "node_modules" ]; then
    echo "检测到 node_modules 不存在，正在安装依赖..."
    if command -v yarn &> /dev/null; then
        yarn install
    elif command -v npm &> /dev/null; then
        npm install
    else
        echo "错误: 未找到 yarn 或 npm"
        exit 1
    fi
fi

# 检查 .env.development 是否存在
if [ ! -f ".env.development" ]; then
    echo "错误: 找不到 .env.development 文件"
    exit 1
fi

echo ""
echo "启动前端开发服务器..."
echo "访问地址: http://127.0.0.1:8080"
echo ""

if command -v yarn &> /dev/null; then
    yarn dev
elif command -v npm &> /dev/null; then
    npm run dev
fi
