#!/bin/bash
# 后端开发启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_ROOT/backend"

echo "========================================="
echo "  Django-Vue3-Admin - 后端开发启动"
echo "========================================="
echo ""

# 检查是否在正确的目录
if [ ! -d "$BACKEND_DIR" ]; then
    echo "错误: 找不到 backend 目录"
    exit 1
fi

cd "$BACKEND_DIR"

# 检查并创建 env.py
if [ ! -f "conf/env.py" ]; then
    if [ -f "conf/env.example.py" ]; then
        echo "检测到 conf/env.py 不存在，正在从 conf/env.example.py 复制..."
        cp conf/env.example.py conf/env.py
        echo "请根据实际情况修改 conf/env.py 中的配置"
    else
        echo "错误: 找不到 conf/env.example.py"
        exit 1
    fi
fi

# 检查是否安装了 Python 依赖
if ! python3 -c "import django" 2>/dev/null; then
    echo "检测到 Django 未安装，正在安装依赖..."
    if [ -f "requirements.txt" ]; then
        pip3 install -r requirements.txt
    else
        echo "错误: 找不到 requirements.txt"
        exit 1
    fi
fi

# 检查数据库是否需要迁移
echo ""
echo "检查数据库迁移..."
python3 manage.py migrate --check 2>/dev/null || {
    echo "需要执行数据库迁移"
    echo "是否执行 makemigrations 和 migrate? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        python3 manage.py makemigrations
        python3 manage.py migrate
    fi
}

echo ""
echo "========================================="
echo "  选择启动方式:"
echo "  1) Django runserver (推荐开发)"
echo "  2) Uvicorn (ASGI, 支持 WebSocket)"
echo "========================================="
echo ""
read -p "请输入选项 (1 或 2, 默认 1): " choice

choice=${choice:-1}

echo ""
echo "启动后端服务器..."
echo "访问地址: http://127.0.0.1:8000"
echo "Swagger 文档: http://127.0.0.1:8000/swagger/"
echo ""

if [ "$choice" = "2" ]; then
    # 使用 Uvicorn
    if command -v uvicorn &> /dev/null; then
        uvicorn application.asgi:application --reload --host 0.0.0.0 --port 8000
    else
        echo "错误: uvicorn 未安装，正在安装..."
        pip3 install uvicorn
        uvicorn application.asgi:application --reload --host 0.0.0.0 --port 8000
    fi
else
    # 使用 Django runserver
    python3 manage.py runserver 0.0.0.0:8000
fi
