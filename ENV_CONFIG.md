# 前后端多环境配置规范

## 概述

本项目实现了统一的前后端多环境配置管理，支持 `dev`（开发）、`test`（测试）、`prod`（生产）三套环境，确保前后端环境切换一致，避免环境不匹配的问题。

## 环境配置文件结构

### 前端（Vue3 + Vite）

```
web/
├── .env                 # 默认环境（开发环境）
├── .env.development     # 开发环境配置
├── .env.test            # 测试环境配置
├── .env.production      # 生产环境配置
└── .env.local_prod      # 本地生产环境配置（保留原有）
```

### 后端（Django）

```
backend/conf/
├── env.py               # 配置加载器（自动根据 APP_ENV 加载对应环境）
├── env.dev.py           # 开发环境配置
├── env.test.py          # 测试环境配置
├── env.prod.py          # 生产环境配置
└── env.example.py       # 配置示例（保留原有）
```

## 环境变量说明

### 前端环境变量

| 变量名 | 说明 | dev | test | prod |
|--------|------|-----|------|------|
| ENV | 环境标识 | development | test | production |
| VITE_PORT | 开发服务器端口 | 8080 | 8080 | 8080 |
| VITE_API_URL | API 基础地址 | http://127.0.0.1:8000 | http://127.0.0.1:8000 | /api |
| VITE_WS_URL | WebSocket 地址 | ws://127.0.0.1:8000 | ws://127.0.0.1:8000 | wss://${HOST} |
| VITE_PM_ENABLED | 是否启用按钮权限 | true | true | true |
| VITE_PUBLIC_PATH | Public Path | / | / | / |
| VITE_DIST_PATH | 构建输出目录 | dist | dist | dist |

### 后端环境变量

| 变量名 | 说明 | dev | test | prod |
|--------|------|-----|------|------|
| DEBUG | 调试模式 | true | true | false |
| DATABASE_ENGINE | 数据库引擎 | mysql | mysql | mysql |
| DATABASE_NAME | 数据库名 | django_vue3_admin_dev | django_vue3_admin_test | django_vue3_admin_prod |
| DATABASE_HOST | 数据库地址 | 127.0.0.1 | 127.0.0.1 | 127.0.0.1 |
| DATABASE_PORT | 数据库端口 | 3306 | 3306 | 3306 |
| DATABASE_USER | 数据库用户名 | root | root | root |
| DATABASE_PASSWORD | 数据库密码 | DVADMIN3 | DVADMIN3 | DVADMIN3 |
| REDIS_DB | Redis DB | 1 | 2 | 0 |
| CELERY_BROKER_DB | Celery DB | 3 | 4 | 3 |
| REDIS_PASSWORD | Redis 密码 | (空) | (空) | (空) |
| LOGIN_NO_CAPTCHA_AUTH | 免验证码登录 | true | false | false |
| ENABLE_LOGIN_ANALYSIS_LOG | 登录分析 | true | false | false |

## 使用方法

### 本地开发环境切换

#### 前端切换环境

```bash
# 开发环境（默认）
cd web
npm run dev

# 测试环境
npm run dev:test

# 生产环境（本地预览）
npm run dev:prod
```

#### 后端切换环境

```bash
cd backend

# 开发环境（默认）
python manage.py runserver

# 测试环境
export APP_ENV=test
python manage.py runserver

# 生产环境
export APP_ENV=prod
python manage.py runserver
```

### 生产部署环境切换

#### 前端构建

```bash
# 构建开发环境
cd web
npm run build:dev

# 构建测试环境
npm run build:test

# 构建生产环境（默认）
npm run build:prod
```

构建后的文件会包含环境标识，方便区分。

#### 后端部署

```bash
cd backend

# 生产环境
export APP_ENV=prod
# 或者在启动脚本中设置
APP_ENV=prod python manage.py runserver
```

## Docker 部署示例

```yaml
# docker-compose.yml
version: '3'
services:
  backend:
    build: ./backend
    environment:
      - APP_ENV=prod
    # ... 其他配置

  frontend:
    build:
      context: ./web
      args:
        - BUILD_ENV=prod
    # ... 其他配置
```

## 注意事项

1. **不要将敏感配置提交到代码仓库**：确保 .env 文件和 env.dev.py/env.test.py/env.prod.py 中的敏感信息（如数据库密码）已替换为占位符
2. **生产环境必须设置合理的安全配置**：
   - DEBUG = False
   - LOGIN_NO_CAPTCHA_AUTH = False
   - 配置安全的数据库和 Redis 密码
3. **前后端环境必须保持一致**：确保前端和后端使用相同的环境标识，避免接口调用错误
4. **默认值兼容**：配置加载器提供了合理的默认值，确保项目在缺少配置时也能正常启动（开发环境）
