import os

SECRET_KEY = os.getenv("APP_SECRET_KEY", "please-replace-me")
DEBUG = True

DATABASE_ENGINE = os.getenv("APP_DB_ENGINE", "django.db.backends.sqlite3")
DATABASE_NAME = os.getenv("APP_DB_NAME", str(BASE_DIR / "db.sqlite3"))
DATABASE_HOST = os.getenv("APP_DB_HOST", "127.0.0.1")
DATABASE_PORT = int(os.getenv("APP_DB_PORT", "3306"))
DATABASE_USER = os.getenv("APP_DB_USER", "")
DATABASE_PASSWORD = os.getenv("APP_DB_PASSWORD", "")

TABLE_PREFIX = os.getenv("APP_TABLE_PREFIX", "dvadmin_")

REDIS_HOST = os.getenv("APP_REDIS_HOST", "127.0.0.1")
REDIS_PORT = int(os.getenv("APP_REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("APP_REDIS_PASSWORD", "")
REDIS_DB = int(os.getenv("APP_REDIS_DB", "1"))
CELERY_BROKER_DB = int(os.getenv("APP_CELERY_BROKER_DB", "3"))
REDIS_URL = os.getenv("APP_REDIS_URL", f"redis://{':' + REDIS_PASSWORD + '@' if REDIS_PASSWORD else ''}{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}")

ENABLE_LOGIN_ANALYSIS_LOG = True
LOGIN_NO_CAPTCHA_AUTH = True

ALLOWED_HOSTS = ["127.0.0.1", "localhost"]
CORS_ORIGIN_ALLOW_ALL = True
CORS_ALLOWED_ORIGINS = ["http://127.0.0.1:8080", "http://localhost:8080"]
STATIC_URL = "/static/"
MEDIA_URL = "/media/"
