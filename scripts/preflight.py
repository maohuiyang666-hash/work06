#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "backend"
WEB_DIR = ROOT_DIR / "web"
SETTINGS_FILE = BACKEND_DIR / "application" / "settings.py"
URLS_FILE = BACKEND_DIR / "application" / "urls.py"
WS_ROUTING_FILE = BACKEND_DIR / "application" / "ws_routing.py"
REQUEST_FILE = WEB_DIR / "src" / "utils" / "request.ts"
WEBSOCKET_FILE = WEB_DIR / "src" / "utils" / "websocket.ts"


class Reporter:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.infos: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def info(self, message: str) -> None:
        self.infos.append(message)


def print_step(message: str) -> None:
    print(f"\n>>> {message}")


def run_command(command: list[str], cwd: Path) -> bool:
    print(f"$ {' '.join(command)}")
    completed = subprocess.run(command, cwd=cwd)
    return completed.returncode == 0


def parse_dotenv(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.split("#", 1)[0].strip().strip('"').strip("'")
        result[key] = value
    return result


def parse_python_env(path: Path) -> dict[str, object]:
    source = path.read_text(encoding="utf-8")
    source = re.sub(r"from\s+application\.settings\s+import\s+BASE_DIR\s*", "", source)
    namespace: dict[str, object] = {"os": os, "BASE_DIR": str(BACKEND_DIR)}
    exec(compile(source, str(path), "exec"), namespace)
    return {key: value for key, value in namespace.items() if key.isupper()}


def normalized_path(value: str) -> str:
    if not value:
        return "/"
    if "://" in value:
        parsed = urlparse(value)
        return parsed.path or "/"
    if value.startswith("/"):
        return value or "/"
    return f"/{value}"


def check_required_file(path: Path, reporter: Reporter, label: str) -> bool:
    if not path.exists():
        reporter.error(f"缺少 {label}: {path}")
        return False
    reporter.info(f"已找到 {label}: {path.relative_to(ROOT_DIR)}")
    return True


def check_backend_env(reporter: Reporter, release_mode: bool) -> bool:
    env_example = BACKEND_DIR / "conf" / "env.example.py"
    env_file = BACKEND_DIR / "conf" / "env.py"
    if not check_required_file(env_example, reporter, "后端配置模板"):
        return False
    if not check_required_file(env_file, reporter, "后端实际配置"):
        return False
    parse_python_env(env_example)
    env_values = parse_python_env(env_file)
    engine = str(env_values.get("DATABASE_ENGINE", "")).strip()
    database_name = str(env_values.get("DATABASE_NAME", "")).strip()
    if not engine:
        reporter.error("backend/conf/env.py 缺少 DATABASE_ENGINE")
    if not database_name:
        reporter.error("backend/conf/env.py 缺少 DATABASE_NAME")
    if engine.endswith("sqlite3"):
        reporter.info("当前后端使用 sqlite，可作为最小可运行数据库依赖")
    else:
        for key in ["DATABASE_HOST", "DATABASE_PORT", "DATABASE_USER", "DATABASE_PASSWORD"]:
            value = env_values.get(key)
            if value in (None, ""):
                reporter.error(f"backend/conf/env.py 缺少 {key}")
        reporter.info("当前后端使用外部数据库，发布前需要确保数据库连接可达")
    debug_value = bool(env_values.get("DEBUG", True))
    if release_mode and debug_value:
        reporter.error("发布前检查要求 backend/conf/env.py 中 DEBUG=False")
    if env_values.get("ALLOWED_HOSTS") in (None, []):
        reporter.error("backend/conf/env.py 缺少 ALLOWED_HOSTS")
    elif env_values.get("ALLOWED_HOSTS") == ["*"]:
        reporter.warn("ALLOWED_HOSTS 仍为 ['*']，生产环境建议收敛为明确域名")
    redis_host = str(env_values.get("REDIS_HOST", "")).strip()
    redis_url = str(env_values.get("REDIS_URL", "")).strip()
    if redis_host or redis_url:
        reporter.info("检测到 Redis 配置，可支撑 Celery 或缓存增强能力")
    else:
        reporter.warn("未检测到 Redis 配置，Celery 与依赖缓存的增强能力可能不可用")
    return not reporter.errors


def check_frontend_env(reporter: Reporter) -> None:
    env_files = [
        WEB_DIR / ".env.development",
        WEB_DIR / ".env.production",
        WEB_DIR / ".env.local_prod",
    ]
    for env_file in env_files:
        if not check_required_file(env_file, reporter, f"前端环境文件 {env_file.name}"):
            continue
        values = parse_dotenv(env_file)
        api_url = values.get("VITE_API_URL", "")
        ws_url = values.get("VITE_WS_URL", api_url)
        if not api_url:
            reporter.error(f"{env_file.name} 缺少 VITE_API_URL")
            continue
        api_path = normalized_path(api_url).rstrip("/") or "/"
        ws_path = normalized_path(ws_url).rstrip("/") or "/"
        if env_file.name != ".env.development" and api_path == "/api":
            reporter.error(f"{env_file.name} 中 VITE_API_URL 不能设置为 /api，当前仓库请求路径已经自带 /api 前缀")
        if env_file.name != ".env.development" and ws_path != "/":
            reporter.error(f"{env_file.name} 中 VITE_WS_URL 应指向根路径 /，否则 websocket.ts 会拼成非 /ws/ 路径")
        if env_file.name == ".env.development" and api_path == "/api":
            reporter.warn(f"{env_file.name} 当前使用相对 /api 可能导致本地联调与生产代理语义混淆")
        reporter.info(f"{env_file.name} 的 API 基础地址为 {api_url}，WebSocket 基础地址为 {ws_url}")


def check_source_alignment(reporter: Reporter) -> None:
    request_source = REQUEST_FILE.read_text(encoding="utf-8")
    websocket_source = WEBSOCKET_FILE.read_text(encoding="utf-8")
    urls_source = URLS_FILE.read_text(encoding="utf-8")
    ws_routing_source = WS_ROUTING_FILE.read_text(encoding="utf-8")
    settings_source = SETTINGS_FILE.read_text(encoding="utf-8")
    if "baseURL: import.meta.env.VITE_API_URL" not in request_source:
        reporter.warn("前端请求基础地址实现已偏离当前预期，请重新确认 request.ts")
    else:
        reporter.info("request.ts 继续使用 VITE_API_URL 作为请求基础地址")
    if "VITE_WS_URL" not in websocket_source and "VITE_WS_URL" not in (WEB_DIR / "src" / "utils" / "baseUrl.ts").read_text(encoding="utf-8"):
        reporter.warn("WebSocket 基础地址未读取 VITE_WS_URL，生产环境可能仍受 API 地址牵连")
    else:
        reporter.info("websocket.ts 通过 baseUrl.ts 读取独立的 WebSocket 地址")
    if 'path("api/init/settings/", InitSettingsViewSet.as_view())' in urls_source:
        reporter.info("后端保留了系统配置初始化接口 /api/init/settings/")
    else:
        reporter.error("后端缺少系统配置初始化接口 /api/init/settings/")
    if 'path("", schema_view.with_ui("swagger", cache_timeout=0)' in urls_source:
        reporter.warn("Swagger UI 当前挂在后端根路径，生产发布时需要明确是否对外暴露")
    else:
        reporter.error("未找到 Swagger UI 路由定义")
    if "static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)" in urls_source:
        reporter.info("后端仍通过 urls.py 暴露媒体文件访问")
    else:
        reporter.warn("未找到媒体文件映射，请确认上传文件访问路径")
    if "path('ws/<str:service_uid>/'" in ws_routing_source:
        reporter.info("后端 WebSocket 路由固定为 /ws/<token>/")
    else:
        reporter.error("未找到后端 WebSocket 路由 /ws/<token>/")
    if '"BACKEND": "channels.layers.InMemoryChannelLayer"' in settings_source:
        reporter.info("当前 WebSocket 默认使用内存通道层，Redis 不是主服务启动前提")
    else:
        reporter.warn("当前通道层不是内存实现，请确认是否需要 Redis 才能启动主服务")
    if "from dvadmin3_celery.settings import *" in settings_source:
        reporter.warn("Celery 插件已接入 settings.py，但 worker 本身仍应视为可选依赖")


def check_backend_commands(reporter: Reporter) -> None:
    manage_ok = run_command(["python3", "manage.py", "check"], BACKEND_DIR)
    if not manage_ok:
        reporter.error("python3 manage.py check 执行失败")
        return
    reporter.info("python3 manage.py check 执行成功")
    db_ok = run_command(
        [
            "python3",
            "manage.py",
            "shell",
            "-c",
            "from django.db import connection; connection.cursor().execute('SELECT 1'); print('db ok')",
        ],
        BACKEND_DIR,
    )
    if db_ok:
        reporter.info("数据库连通性检查通过")
    else:
        reporter.error("数据库连通性检查失败")


def run_web_build(reporter: Reporter, build_target: str) -> None:
    if build_target == "skip":
        reporter.info("已跳过前端构建检查")
        return
    if build_target == "embedded":
        command = ["npm", "run", "build:local"]
    else:
        command = ["npm", "run", "build"]
    ok = run_command(command, WEB_DIR)
    if ok:
        reporter.info("前端构建检查通过")
    else:
        reporter.error("前端构建失败")


def print_summary(reporter: Reporter) -> None:
    print_step("检查结果")
    for message in reporter.infos:
        print(f"[INFO] {message}")
    for message in reporter.warnings:
        print(f"[WARN] {message}")
    for message in reporter.errors:
        print(f"[ERROR] {message}")
    print(f"\n汇总: {len(reporter.errors)} 个错误, {len(reporter.warnings)} 个警告")


def main() -> int:
    parser = argparse.ArgumentParser(description="仓库发布前自检")
    parser.add_argument("--mode", choices=["release", "dev"], default="release")
    parser.add_argument("--build-target", choices=["standard", "embedded", "skip"], default="standard")
    args = parser.parse_args()
    reporter = Reporter()

    print_step("检查关键文件")
    for path, label in [
        (SETTINGS_FILE, "后端 settings.py"),
        (URLS_FILE, "后端 urls.py"),
        (WS_ROUTING_FILE, "后端 ws_routing.py"),
        (REQUEST_FILE, "前端 request.ts"),
        (WEBSOCKET_FILE, "前端 websocket.ts"),
    ]:
        check_required_file(path, reporter, label)

    print_step("检查后端配置")
    check_backend_env(reporter, release_mode=args.mode == "release")

    print_step("检查前端环境")
    check_frontend_env(reporter)

    print_step("检查前后端路径约定")
    check_source_alignment(reporter)

    print_step("执行前端构建")
    run_web_build(reporter, args.build_target)

    print_step("执行后端基础检查")
    if not reporter.errors:
        check_backend_commands(reporter)
    else:
        reporter.warn("由于前置配置错误，已跳过 Django 基础检查")

    print_summary(reporter)
    return 1 if reporter.errors else 0


if __name__ == "__main__":
    sys.exit(main())
