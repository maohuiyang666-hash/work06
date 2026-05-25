# Django-Vue3-Admin 统一启动和发布指南

## 目录结构说明

```
.
├── web/                 # 前端项目
│   ├── package.json
│   ├── .env            # 默认环境配置
│   ├── .env.development # 开发环境配置
│   └── .env.production  # 生产环境配置
├── backend/            # 后端项目
│   ├── manage.py
│   ├── main.py
│   ├── docker_start.sh
│   └── conf/
│       ├── env.example.py  # 配置示例
│       └── env.py          # 实际配置（需创建）
└── scripts/            # 统一脚本（新增）
    ├── dev.sh         # 前端开发启动
    ├── backend.sh     # 后端开发启动
    ├── check.sh       # 发布前检查
    └── build.sh       # 发布构建
```

## 快速开始

### 前置要求

- Python >= 3.9
- Node.js >= 16
- npm 或 yarn
- MySQL 8.0+ (可选，默认 SQLite)
- Redis (可选)

### 开发环境启动

#### 方式一：使用统一脚本（推荐）

```bash
# 1. 赋予脚本执行权限
chmod +x scripts/*.sh

# 2. 启动后端（终端 1）
./scripts/backend.sh

# 3. 启动前端（终端 2）
./scripts/dev.sh
```

#### 方式二：手动启动

**前端：**
```bash
cd web
yarn install  # 或 npm install
yarn dev      # 或 npm run dev
```

**后端：**
```bash
cd backend

# 创建配置文件
cp conf/env.example.py conf/env.py
# 编辑 conf/env.py 配置数据库等

# 安装依赖
pip install -r requirements.txt

# 数据库迁移
python manage.py makemigrations
python manage.py migrate
python manage.py init
python manage.py init_area  # 可选：初始化地区数据

# 启动
python manage.py runserver 0.0.0.0:8000
# 或使用 uvicorn（支持 WebSocket）
uvicorn application.asgi:application --reload --host 0.0.0.0 --port 8000
```

### 最小化运行模式（无 MySQL/Redis）

如果不想安装 MySQL 和 Redis，可以使用 SQLite 进行快速开发：

```bash
cd backend
cp conf/env.minimal.py conf/env.py
pip install -r requirements.txt
python manage.py migrate
python manage.py init
python manage.py runserver 0.0.0.0:8000
```

## 发布流程

### 1. 发布前检查

```bash
./scripts/check.sh
```

检查内容包括：
- ✅ 前端配置文件存在性
- ✅ 后端配置文件存在性
- ✅ Django 系统检查
- ✅ DEBUG 模式状态
- ✅ 前端构建能力
- ✅ 前后端地址配置匹配

### 2. 构建发布

```bash
./scripts/build.sh
```

这个脚本会：
1. 自动运行发布前检查
2. 安装前端依赖（如需要）
3. 执行前端构建
4. 输出构建产物到 `web/dist`

### 3. 部署

#### Docker Compose 部署（推荐）

项目已提供 `docker-compose.yml`，使用方式：

```bash
# 启动所有服务
docker-compose up -d

# 初始化数据（首次）
docker exec -ti dvadmin3-django bash
python manage.py makemigrations
python manage.py migrate
python manage.py init_area
python manage.py init
exit

# 访问
# 前端：http://127.0.0.1:8080
# 后端：http://127.0.0.1:8080/api
# Swagger：http://127.0.0.1:8080/swagger/
```

#### 手动部署

1. **后端部署**
   - 确保 `conf/env.py` 配置正确
   - 确保 `DEBUG = False`
   - 收集静态文件：`python manage.py collectstatic`
   - 使用 uvicorn/gunicorn 启动

2. **前端部署**
   - 将 `web/dist` 目录内容部署到静态服务器
   - 或使用 nginx 代理（参考 `docker_env/nginx/`）

## 发布前检查清单

| 检查项 | 对应文件/模块 | 说明 |
|--------|-------------|------|
| 前端 .env.production | web/.env.production | 生产环境 API 地址等配置 |
| 后端 env.py | backend/conf/env.py | 数据库、Redis、DEBUG 等配置 |
| DEBUG 模式 | backend/conf/env.py | 生产环境必须设为 False |
| Django 系统检查 | python manage.py check | 检查 Django 配置和应用 |
| 前端构建 | web/package.json | 确保 build 命令可用 |
| 前后端 API 地址匹配 | web/.env.production / backend/conf/env.py | 确保接口地址正确 |
| SECRET_KEY | backend/application/settings.py | 生产环境应使用强密钥 |
| 静态文件配置 | backend/application/settings.py | STATIC_ROOT、MEDIA_ROOT 等 |
| WebSocket 配置 | web/src/utils/websocket.ts / backend/application/settings.py | 确保 WebSocket 地址和后端匹配 |

## 开发与生产环境差异

### 前端

| 配置项 | 开发环境 (.env.development) | 生产环境 (.env.production) |
|--------|---------------------------|--------------------------|
| VITE_API_URL | http://127.0.0.1:8000 | /api (nginx 代理) |
| VITE_PORT | 8080 | - |
| VITE_OPEN | false | - |

### 后端

| 配置项 | 开发环境 | 生产环境 |
|--------|--------|--------|
| DEBUG | True | False |
| DATABASE_ENGINE | sqlite3 或 mysql | mysql (推荐) |
| REDIS | 可选 | 推荐配置 |
| ALLOWED_HOSTS | ["*"] | 具体域名 |
| 静态文件 | STATICFILES_DIRS | STATIC_ROOT + collectstatic |

## 常见问题

### 1. 后端有几种启动方式？应该用哪种？

| 方式 | 文件 | 适用场景 | 说明 |
|------|------|---------|------|
| manage.py runserver | backend/manage.py | 开发 | Django 自带，简单方便 |
| main.py (uvicorn) | backend/main.py | 生产 | 多 worker，性能更好 |
| docker_start.sh | backend/docker_start.sh | Docker | 容器化部署 |

**推荐：**
- 开发时用 `manage.py runserver` 或 `uvicorn --reload`
- 生产时用 uvicorn 或 docker-compose

### 2. 最容易出问题的三个点

**1) 配置文件缺失或错配**
- `backend/conf/env.py` 经常被忘记复制
- 前后端 API 地址不匹配（特别是部署时）
- 解决方案：使用 `scripts/check.sh` 检查

**2) 数据库迁移问题**
- 忘记执行 `makemigrations` 或 `migrate`
- 生产和开发数据库不一致
- 解决方案：发布流程中明确迁移步骤

**3) WebSocket 连接问题**
- 生产环境使用 nginx 代理时需要配置 WebSocket 支持
- 前端 WebSocket 地址配置错误
- 解决方案：参考 docker_env/nginx/my.conf 的配置

### 3. 哪些功能依赖 Redis？

- 缓存（可选）
- Celery 异步任务（需安装 celery 插件）
- WebSocket Channel Layer（可选，默认用内存）

不使用 Redis 时系统仍可正常运行，只是部分高级功能不可用。

## 默认账号

- 账号：superadmin
- 密码：admin123456
