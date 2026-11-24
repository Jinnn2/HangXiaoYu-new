"""API 测试：每次运行新建一个测试数据库并安装 db/01~09。

需要一个可连接的 PostgreSQL（有建库权限），通过环境变量指定：
    HXY_TEST_ADMIN_URL=postgresql://postgres:密码@127.0.0.1:5432/postgres
"""

import os
from pathlib import Path

import psycopg
import pytest

ADMIN_URL = os.environ.get("HXY_TEST_ADMIN_URL", "postgresql://postgres@127.0.0.1:5432/postgres")
TEST_DB = "hxy_api_test"
DB_DIR = Path(__file__).resolve().parents[2] / "db"
FILES = ["01_schema.sql", "02_indexes.sql", "03_triggers.sql", "04_functions_user.sql",
         "05_functions_listing.sql", "06_functions_valuation.sql", "07_functions_trade.sql",
         "08_views.sql", "09_seed.sql"]

with psycopg.connect(ADMIN_URL, autocommit=True) as conn:
    conn.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
    conn.execute(f"CREATE DATABASE {TEST_DB}")
TEST_URL = psycopg.conninfo.make_conninfo(ADMIN_URL, dbname=TEST_DB)
with psycopg.connect(TEST_URL, autocommit=True) as conn:
    for f in FILES:
        # ClientCursor 走简单查询协议，可以一次发送整份含多条语句的 SQL 文件
        psycopg.ClientCursor(conn).execute((DB_DIR / f).read_text(encoding="utf-8"))

os.environ["HXY_DATABASE_URL"] = TEST_URL
os.environ["HXY_TASK_INTERVAL_SECONDS"] = "0"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client_factory():
    with TestClient(app) as base:
        def make():
            # 不进入上下文，不重复触发 lifespan；共享 base 打开的连接池，各自保存 Cookie
            return TestClient(app)
        yield make, base


@pytest.fixture
def anon(client_factory):
    make, _ = client_factory
    return make()


def login(client, student_no, password="123456"):
    r = client.post("/api/auth/login", json={"student_no": student_no, "password": password})
    assert r.status_code == 200, r.text
    return client


@pytest.fixture
def lin(client_factory):  # 演示数据中的林同学（买家）
    return login(client_factory[0](), "23370001")


@pytest.fixture
def wang(client_factory):  # 王同学（卖家）
    return login(client_factory[0](), "23370002")


@pytest.fixture
def admin(client_factory):
    return login(client_factory[0](), "admin")
