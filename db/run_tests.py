"""航小鱼数据库自测运行器（Windows / macOS / Linux 通用）。

在系统临时目录新建一个隔离的 PostgreSQL 实例（端口 55432、仅本机、无密码），
安装 db/01~08，然后每个测试文件在一份全新的数据库副本里运行，最后做并发测试和演示数据检查。
结束后自动停止并删除该实例，不会连接或修改任何已有数据库。

用法：
    python db/run_tests.py
    python db/run_tests.py --pg-bin "C:\\Program Files\\PostgreSQL\\18\\bin"

只依赖 PostgreSQL 自带的 initdb / pg_ctl / psql，不需要安装任何 Python 包。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DB_DIR = Path(__file__).resolve().parent
PORT = "55432"
INSTALL_FILES = [
    "01_schema.sql", "02_indexes.sql", "03_triggers.sql", "04_functions_user.sql",
    "05_functions_listing.sql", "06_functions_valuation.sql", "07_functions_trade.sql",
    "08_views.sql",
]
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def find_pg_bin(explicit: str | None) -> Path:
    candidates = []
    if explicit:
        candidates.append(Path(explicit))
    if os.environ.get("PG_BIN"):
        candidates.append(Path(os.environ["PG_BIN"]))
    for version in ("18", "17", "16"):
        candidates.append(Path(rf"C:\Program Files\PostgreSQL\{version}\bin"))
        candidates.append(Path(f"/usr/lib/postgresql/{version}/bin"))
    found = shutil.which("initdb")
    if found:
        candidates.append(Path(found).parent)
    exe = ".exe" if os.name == "nt" else ""
    for c in candidates:
        if (c / f"initdb{exe}").exists() and (c / f"psql{exe}").exists():
            return c
    sys.exit("找不到 PostgreSQL 的 bin 目录，请用 --pg-bin 指定（例如 C:\\Program Files\\PostgreSQL\\18\\bin）")


class Cluster:
    def __init__(self, pg_bin: Path):
        self.bin = pg_bin
        self.dir = Path(tempfile.mkdtemp(prefix="hxy_pgtest_"))
        self.data = self.dir / "data"
        self.started = False

    def tool(self, name: str) -> str:
        return str(self.bin / (name + (".exe" if os.name == "nt" else "")))

    def start(self) -> None:
        subprocess.run([self.tool("initdb"), "-D", str(self.data), "-U", "hxy_test", "--auth=trust",
                        "--encoding=UTF8", "--locale=C", "--no-instructions"],
                       check=True, stdout=subprocess.DEVNULL, creationflags=NO_WINDOW)
        opts = f"-p {PORT} -h 127.0.0.1" + ("" if os.name == "nt" else f" -k {self.dir}")
        subprocess.run([self.tool("pg_ctl"), "-D", str(self.data), "-l", str(self.dir / "server.log"),
                        "-o", opts, "-w", "start"], check=True, stdout=subprocess.DEVNULL,
                       creationflags=NO_WINDOW)
        self.started = True

    def stop(self) -> None:
        if self.started:
            subprocess.run([self.tool("pg_ctl"), "-D", str(self.data), "-m", "fast", "-w", "stop"],
                           stdout=subprocess.DEVNULL, creationflags=NO_WINDOW)
        shutil.rmtree(self.dir, ignore_errors=True)

    def psql_args(self, db: str) -> list[str]:
        return [self.tool("psql"), "-h", "127.0.0.1", "-p", PORT, "-U", "hxy_test", "-d", db,
                "-X", "-q", "-v", "ON_ERROR_STOP=1"]

    def run_file(self, db: str, path: Path) -> str:
        r = subprocess.run(self.psql_args(db) + ["-f", str(path)], cwd=path.parent,
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           creationflags=NO_WINDOW)
        if r.returncode != 0:
            raise RuntimeError(f"{path.name} 失败：\n{r.stderr.strip()}")
        return r.stderr

    def sql(self, db: str, sql: str) -> str:
        r = subprocess.run(self.psql_args(db) + ["-A", "-t", "-c", sql], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", creationflags=NO_WINDOW)
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip())
        return r.stdout.strip()

    def start_session(self, db: str, script: str) -> subprocess.Popen:
        p = subprocess.Popen(self.psql_args(db) + ["-A", "-t"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             encoding="utf-8", errors="replace", creationflags=NO_WINDOW)
        assert p.stdin is not None
        p.stdin.write(script)
        p.stdin.close()
        return p


def print_notices(stderr: str) -> int:
    count = 0
    for line in stderr.splitlines():
        if "ok - " in line:
            count += 1
            print("    √", line.split("ok - ", 1)[1])
    return count


def concurrency_tests(c: Cluster) -> None:
    """两个独立会话争抢同一资源：第一个会话持锁 2 秒，第二个必须等待并失败。"""
    db = "t_concurrency"
    c.sql("postgres", f"CREATE DATABASE {db} TEMPLATE hxy_template")
    ids = c.sql(db, """
        SELECT concat_ws(',', s, b1, b2, l1, l2, o) FROM (
          SELECT hxy_test.new_user('60001', 0) s, hxy_test.new_user('60002') b1,
                 hxy_test.new_user('60003') b2) u,
        LATERAL (SELECT hxy.create_listing(u.s, 1, '争抢商品', '', 4::SMALLINT, 100, 50) l1,
                        hxy.create_listing(u.s, 1, '结算商品', '', 4::SMALLINT, 100, 60) l2) l,
        LATERAL (SELECT hxy.place_order(l.l2, u.b1) o) o;""")
    s, b1, b2, l1, l2, o = ids.split(",")
    c.sql(db, f"SELECT hxy.pay_order({o}, {b1}); SELECT hxy.mark_order_delivered({o}, {s});")

    def race(name: str, first: str, second: str, check: str) -> None:
        p1 = c.start_session(db, f"BEGIN; {first}; SELECT pg_sleep(2); COMMIT;")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:  # 等第一个会话真正拿到锁
            if c.sql(db, "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%pg_sleep(2)%' "
                         "AND state = 'active' AND pid <> pg_backend_pid()") == "1":
                break
            time.sleep(0.05)
        t0 = time.monotonic()
        p2 = c.start_session(db, f"{second};")
        _, err2 = p2.communicate(timeout=15)
        waited = time.monotonic() - t0
        _, err1 = p1.communicate(timeout=15)
        if p1.returncode != 0:
            raise RuntimeError(f"{name}：第一个会话失败 {err1}")
        if p2.returncode == 0:
            raise RuntimeError(f"{name}：第二个会话本应失败却成功")
        result = c.sql(db, check)
        if result != "t":
            raise RuntimeError(f"{name}：数据库核对失败")
        print(f"    √ {name}（第二个会话等待 {waited:.1f}s 后被拒绝：{err2.strip().splitlines()[0][:60]}）")

    race("两名买家同时下单同一商品",
         f"SELECT hxy.place_order({l1}, {b1})", f"SELECT hxy.place_order({l1}, {b2})",
         f"SELECT count(*) = 1 FROM hxy.trade_order WHERE listing_id = {l1}")
    race("买家确认收货与未收到反馈同时提交",
         f"SELECT hxy.complete_order({o}, 'BUYER_CONFIRMED', {b1})",
         f"SELECT hxy.open_order_review({o}, 'NOT_RECEIVED', {b1})",
         f"SELECT count(*) = 1 AND hxy_test.books_balanced() FROM hxy.point_transfer "
         f"WHERE order_id = {o} AND event_type = 'SETTLEMENT'")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--pg-bin")
    args = ap.parse_args()
    c = Cluster(find_pg_bin(args.pg_bin))
    total = 0
    try:
        print(f"启动隔离实例：{c.dir}")
        c.start()
        print(c.sql("postgres", "SELECT version()").split(",")[0])
        c.sql("postgres", "CREATE DATABASE hxy_template")
        for f in INSTALL_FILES:
            c.run_file("hxy_template", DB_DIR / f)
        print("安装 01~08 完成")
        c.run_file("hxy_template", DB_DIR / "tests" / "00_helpers.sql")

        for test in sorted((DB_DIR / "tests").glob("t*.sql")):
            db = "t_" + test.stem
            c.sql("postgres", f"CREATE DATABASE {db} TEMPLATE hxy_template")
            print(f"RUN {test.name}")
            total += print_notices(c.run_file(db, test))

        print("RUN 并发测试")
        concurrency_tests(c)
        total += 2

        print("RUN 09_seed.sql 演示数据")
        c.sql("postgres", "CREATE DATABASE t_seed")
        for f in INSTALL_FILES + ["09_seed.sql"]:
            c.run_file("t_seed", DB_DIR / f)
        stats = c.sql("t_seed", "SELECT balance_sum = 0 AND mismatched_accounts = 0 AND completed_orders = 22 "
                                "FROM hxy.v_platform_stats")
        if stats != "t":
            raise RuntimeError("演示数据对账失败")
        print("    √ 演示数据安装成功且账目平衡")
        total += 1
        print(f"\nPASS：全部 {total} 项检查通过。")
    except Exception as exc:  # noqa: BLE001
        print(f"\nFAIL：{exc}")
        log = c.dir / "server.log"
        if log.exists():
            print("--- server.log 末尾 ---")
            print("".join(log.read_text(encoding="utf-8", errors="replace").splitlines(True)[-15:]))
        sys.exit(1)
    finally:
        c.stop()


if __name__ == "__main__":
    main()
