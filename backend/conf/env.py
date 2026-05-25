import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

ENV_ALIASES = {
    "development": "dev",
    "testing": "test",
    "production": "prod",
}
ENV_LABELS = {
    "dev": "开发",
    "test": "测试",
    "prod": "生产",
}
SUPPORTED_ENVS = {"dev", "test", "prod"}


def _normalize_env(value):
    normalized = (value or "dev").strip().lower()
    normalized = ENV_ALIASES.get(normalized, normalized)
    if normalized not in SUPPORTED_ENVS:
        return "dev"
    return normalized


APP_ENV = _normalize_env(os.getenv("APP_ENV") or os.getenv("DJANGO_ENV") or os.getenv("ENV"))
APP_ENV_LABEL = ENV_LABELS.get(APP_ENV, "开发")


CONFIG_WARNINGS = []
CONFIG_ERRORS = []
LEGACY_CONFIG = {}
LOADED_CONFIG_FILES = []


def _load_python_config(config_path):
    if not config_path.exists():
        return
    namespace = {
        "os": os,
        "Path": Path,
        "BASE_DIR": BASE_DIR,
    }
    with open(config_path, "r", encoding="utf-8") as file:
        code = compile(file.read(), str(config_path), "exec")
        exec(code, namespace)
    for key, value in namespace.items():
        if key.isupper():
            LEGACY_CONFIG[key] = value
    LOADED_CONFIG_FILES.append(str(config_path))


for file_name in [f"env.{APP_ENV}.py", "env.local.py", f"env.{APP_ENV}.local.py"]:
    _load_python_config(BASE_DIR / "conf" / file_name)


def _pick_env(keys):
    if isinstance(keys, str):
        keys = [keys]
    for key in keys:
        value = os.getenv(key)
        if value not in (None, ""):
            return value
    return None


def _pick_legacy(keys):
    if isinstance(keys, str):
        keys = [keys]
    for key in keys:
        value = LEGACY_CONFIG.get(key)
        if value not in (None, ""):
            return value
    return None


def _get_value(env_keys, legacy_keys=None, default=None):
    env_value = _pick_env(env_keys)
    if env_value not in (None, ""):
        return env_value
    if legacy_keys:
        legacy_value = _pick_legacy(legacy_keys)
        if legacy_value not in (None, ""):
            return legacy_value
    return default


def _to_bool(value, default=False):
    if value in (None, ""):
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _to_int(value, default):
    if value in (None, ""):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _to_list(value, default=None):
    if value in (None, ""):
        return list(default or [])
    if isinstance(value, (list, tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]
    return [item.strip() for item in str(value).split(",") if item.strip()]


def _build_redis_url(password, host, port, db):
    auth = f":{password}@" if password else ""
    return f"redis://{auth}{host}:{port}/{db}"


SECRET_KEY = _get_value(
    ["APP_SECRET_KEY", "SECRET_KEY"],
    ["SECRET_KEY"],
    "django-insecure-dev-secret-key",
)
if APP_ENV == "prod" and SECRET_KEY == "django-insecure-dev-secret-key":
    CONFIG_ERRORS.append("缺少 APP_SECRET_KEY")

DEBUG = _to_bool(
    _get_value(["APP_DEBUG", "DEBUG"], ["DEBUG"], APP_ENV == "dev"),
    APP_ENV == "dev",
)
ENABLE_LOGIN_ANALYSIS_LOG = _to_bool(
    _get_value(
        ["APP_LOGIN_ANALYSIS_ENABLED", "ENABLE_LOGIN_ANALYSIS_LOG"],
        ["ENABLE_LOGIN_ANALYSIS_LOG"],
        APP_ENV == "dev",
    ),
    APP_ENV == "dev",
)

login_captcha_value = _pick_env("APP_LOGIN_CAPTCHA_ENABLED")
if login_captcha_value is None:
    legacy_login_no_captcha = _get_value("LOGIN_NO_CAPTCHA_AUTH", ["LOGIN_NO_CAPTCHA_AUTH"], None)
    if legacy_login_no_captcha is None:
        APP_LOGIN_CAPTCHA_ENABLED = APP_ENV != "dev"
    else:
        APP_LOGIN_CAPTCHA_ENABLED = not _to_bool(legacy_login_no_captcha, False)
else:
    APP_LOGIN_CAPTCHA_ENABLED = _to_bool(login_captcha_value, APP_ENV != "dev")
LOGIN_NO_CAPTCHA_AUTH = not APP_LOGIN_CAPTCHA_ENABLED

ALLOWED_HOSTS = _to_list(
    _get_value(["APP_ALLOWED_HOSTS", "ALLOWED_HOSTS"], ["ALLOWED_HOSTS"], "*" if APP_ENV != "prod" else ""),
    ["*"] if APP_ENV != "prod" else [],
)
if APP_ENV == "prod" and not ALLOWED_HOSTS:
    CONFIG_ERRORS.append("缺少 APP_ALLOWED_HOSTS")

COLUMN_EXCLUDE_APPS = _to_list(
    _get_value(["APP_COLUMN_EXCLUDE_APPS"], ["COLUMN_EXCLUDE_APPS"], []),
    [],
)

CORS_ORIGIN_ALLOW_ALL = _to_bool(
    _get_value(["APP_CORS_ALLOW_ALL", "CORS_ORIGIN_ALLOW_ALL"], ["CORS_ORIGIN_ALLOW_ALL"], APP_ENV == "dev"),
    APP_ENV == "dev",
)
CORS_ALLOW_CREDENTIALS = _to_bool(
    _get_value(["APP_CORS_ALLOW_CREDENTIALS", "CORS_ALLOW_CREDENTIALS"], ["CORS_ALLOW_CREDENTIALS"], True),
    True,
)
CORS_ALLOWED_ORIGINS = _to_list(
    _get_value(["APP_CORS_ALLOWED_ORIGINS", "CORS_ALLOWED_ORIGINS"], ["CORS_ALLOWED_ORIGINS"], []),
    [],
)
CSRF_TRUSTED_ORIGINS = _to_list(
    _get_value(["APP_CSRF_TRUSTED_ORIGINS", "CSRF_TRUSTED_ORIGINS"], ["CSRF_TRUSTED_ORIGINS"], CORS_ALLOWED_ORIGINS),
    CORS_ALLOWED_ORIGINS,
)
if APP_ENV == "prod" and not CORS_ORIGIN_ALLOW_ALL and not CORS_ALLOWED_ORIGINS:
    CONFIG_WARNINGS.append("生产环境未配置 APP_CORS_ALLOWED_ORIGINS，当前仅允许同源请求")

DATABASE_ENGINE = _get_value(
    ["APP_DB_ENGINE", "DATABASE_ENGINE"],
    ["DATABASE_ENGINE"],
    "django.db.backends.sqlite3" if APP_ENV != "prod" else "django.db.backends.mysql",
)
DATABASE_PORT = _to_int(
    _get_value(["APP_DB_PORT", "DATABASE_PORT"], ["DATABASE_PORT"], 3306),
    3306,
)
DATABASE_NAME = _get_value(
    ["APP_DB_NAME", "DATABASE_NAME"],
    ["DATABASE_NAME"],
    str(BASE_DIR / "db.sqlite3") if DATABASE_ENGINE == "django.db.backends.sqlite3" else None,
)
DATABASE_HOST = _get_value(["APP_DB_HOST", "DATABASE_HOST"], ["DATABASE_HOST"], "127.0.0.1")
DATABASE_USER = _get_value(["APP_DB_USER", "DATABASE_USER"], ["DATABASE_USER"], "")
DATABASE_PASSWORD = _get_value(["APP_DB_PASSWORD", "DATABASE_PASSWORD"], ["DATABASE_PASSWORD"], "")

if DATABASE_ENGINE != "django.db.backends.sqlite3":
    missing_database_fields = []
    if not DATABASE_NAME:
        missing_database_fields.append("APP_DB_NAME")
    if not DATABASE_HOST:
        missing_database_fields.append("APP_DB_HOST")
    if not DATABASE_USER:
        missing_database_fields.append("APP_DB_USER")
    if APP_ENV == "prod" and missing_database_fields:
        CONFIG_ERRORS.append("缺少数据库配置: " + ", ".join(missing_database_fields))
else:
    DATABASE_HOST = ""
    DATABASE_USER = ""
    DATABASE_PASSWORD = ""
    DATABASE_PORT = ""

TABLE_PREFIX = _get_value(["APP_TABLE_PREFIX", "TABLE_PREFIX"], ["TABLE_PREFIX"], "dvadmin_")

REDIS_HOST = _get_value(["APP_REDIS_HOST", "REDIS_HOST"], ["REDIS_HOST"], "127.0.0.1")
REDIS_PORT = _to_int(
    _get_value(["APP_REDIS_PORT", "REDIS_PORT"], ["REDIS_PORT"], 6379),
    6379,
)
REDIS_PASSWORD = _get_value(["APP_REDIS_PASSWORD", "REDIS_PASSWORD"], ["REDIS_PASSWORD"], "")
REDIS_DB = _to_int(_get_value(["APP_REDIS_DB", "REDIS_DB"], ["REDIS_DB"], 1 if APP_ENV == "dev" else 2 if APP_ENV == "test" else 0), 1)
CELERY_BROKER_DB = _to_int(
    _get_value(["APP_CELERY_BROKER_DB", "CELERY_BROKER_DB"], ["CELERY_BROKER_DB"], 3),
    3,
)
CELERY_RESULT_DB = _to_int(
    _get_value(["APP_CELERY_RESULT_DB"], ["CELERY_RESULT_DB"], CELERY_BROKER_DB),
    CELERY_BROKER_DB,
)
REDIS_URL = _get_value(
    ["APP_REDIS_URL", "REDIS_URL"],
    ["REDIS_URL"],
    _build_redis_url(REDIS_PASSWORD, REDIS_HOST, REDIS_PORT, REDIS_DB),
)
CELERY_BROKER_URL = _get_value(
    ["APP_CELERY_BROKER_URL", "CELERY_BROKER_URL"],
    ["CELERY_BROKER_URL"],
    _build_redis_url(REDIS_PASSWORD, REDIS_HOST, REDIS_PORT, CELERY_BROKER_DB),
)
CELERY_RESULT_BACKEND = _get_value(
    ["APP_CELERY_RESULT_BACKEND", "CELERY_RESULT_BACKEND"],
    ["CELERY_RESULT_BACKEND"],
    _build_redis_url(REDIS_PASSWORD, REDIS_HOST, REDIS_PORT, CELERY_RESULT_DB),
)
CHANNEL_REDIS_DB = _to_int(
    _get_value(["APP_CHANNEL_REDIS_DB"], ["CHANNEL_REDIS_DB"], REDIS_DB),
    REDIS_DB,
)
CHANNEL_REDIS_URL = _get_value(
    ["APP_CHANNEL_REDIS_URL"],
    ["CHANNEL_REDIS_URL"],
    _build_redis_url(REDIS_PASSWORD, REDIS_HOST, REDIS_PORT, CHANNEL_REDIS_DB),
)
CHANNEL_LAYER_BACKEND = _get_value(
    ["APP_CHANNEL_BACKEND"],
    ["CHANNEL_LAYER_BACKEND"],
    "memory" if APP_ENV == "dev" else "redis",
)
if CHANNEL_LAYER_BACKEND == "redis":
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {
                "hosts": [CHANNEL_REDIS_URL],
            },
        }
    }
else:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels.layers.InMemoryChannelLayer",
        }
    }

STATIC_URL = _get_value(["APP_STATIC_URL", "STATIC_URL"], ["STATIC_URL"], "/static/")
MEDIA_URL = _get_value(["APP_MEDIA_URL", "MEDIA_URL"], ["MEDIA_URL"], "/media/")
STATIC_ROOT = _get_value(["APP_STATIC_ROOT", "STATIC_ROOT"], ["STATIC_ROOT"], str(BASE_DIR / "staticfiles"))
MEDIA_ROOT = _get_value(["APP_MEDIA_ROOT", "MEDIA_ROOT"], ["MEDIA_ROOT"], str(BASE_DIR / "media"))
static_dir_value = _get_value(["APP_STATIC_DIR"], ["STATIC_DIR"], str(BASE_DIR / "static"))
STATICFILES_DIRS = [static_dir_value] if static_dir_value else []
WEB_TEMPLATE_DIR = _get_value(["APP_WEB_TEMPLATE_DIR"], ["WEB_TEMPLATE_DIR"], str(BASE_DIR / "templates" / "web"))

if APP_ENV == "prod" and CONFIG_ERRORS:
    error_text = "\n".join([f"- {message}" for message in CONFIG_ERRORS])
    raise RuntimeError(f"配置加载失败，当前环境: {APP_ENV}\n{error_text}")

if CONFIG_WARNINGS:
    for warning in CONFIG_WARNINGS:
        print(f"[config warning] {warning}", file=sys.stderr)
