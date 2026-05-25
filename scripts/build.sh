#!/bin/bash
# 发布构建脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web"

echo "========================================="
echo "  Django-Vue3-Admin - 发布构建"
echo "========================================="
echo ""

# 首先运行检查脚本
echo "第一步: 运行发布前检查..."
"$SCRIPT_DIR/check.sh"

echo ""
echo "第二步: 构建前端..."
cd "$WEB_DIR"

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

echo ""
echo "正在构建前端..."
if command -v yarn &> /dev/null; then
    yarn build
elif command -v npm &> /dev/null; then
    npm run build
fi

echo ""
echo "========================================="
echo "  构建完成！"
echo "========================================="
echo ""
echo "前端构建产物目录: $WEB_DIR/dist"
echo ""
echo "下一步操作建议:"
echo "  - 将 dist 目录部署到静态文件服务器"
echo "  - 或配置 nginx 代理前端和后端"
echo "  - 后端保持运行即可"
