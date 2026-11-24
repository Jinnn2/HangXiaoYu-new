"""只用 psql 启动两个独立数据库会话；业务 SQL 仍由 PostgreSQL 原生函数执行。"""

import argparse
import subprocess
import sys
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--psql", required=True)
    args = parser.parse_args()
    common = [args.psql, "-h", "127.0.0.1", "-p", "55432", "-U", "demo_test",
              "-d", "postgres", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1"]
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    def scalar(sql: str) -> str:
        result = subprocess.run(common + ["-c", sql], capture_output=True, text=True,
                                encoding="utf-8", errors="replace", creationflags=flags)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout.strip()

    def wait_until_first_holds_lock(process: subprocess.Popen[str], sleep_seconds: int) -> None:
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise AssertionError("首个会话未能保持事务")
            count = scalar("SELECT count(*) FROM pg_stat_activity "
                           "WHERE pid <> pg_backend_pid() AND state = 'active' "
                           f"AND query LIKE '%SELECT pg_sleep({sleep_seconds})%'")
            if int(count) >= 1:
                return
            time.sleep(0.05)
        raise AssertionError("未观察到首个会话已取得锁并进入等待")

    def compete(label: str, first_sql: str, second_sql: str) -> None:
        first = subprocess.Popen(
            common + ["-c", "BEGIN;", "-c", first_sql,
                      "-c", "SELECT pg_sleep(3);", "-c", "COMMIT;"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", errors="replace", creationflags=flags,
        )
        try:
            wait_until_first_holds_lock(first, 3)
            started = time.monotonic()
            second = subprocess.run(common + ["-c", second_sql], capture_output=True,
                                    text=True, encoding="utf-8", errors="replace",
                                    creationflags=flags, timeout=8)
            waited = time.monotonic() - started
            first_out, first_err = first.communicate(timeout=8)
            if first.returncode != 0:
                raise AssertionError(f"{label}：首个会话失败：{first_err}")
            if second.returncode == 0:
                raise AssertionError(f"{label}：第二个会话意外成功：{second.stdout}")
            if waited < 1.0:
                raise AssertionError(f"{label}：第二个会话没有等待第一个事务，耗时 {waited:.2f}s")
            print(f"PASS {label}: first=success, second=rejected, waited={waited:.2f}s")
        finally:
            if first.poll() is None:
                first.kill()
                first.communicate()

    compete("同一商品双买家下单",
            "SELECT trade_demo.place_order(5014, 1001);",
            "SELECT trade_demo.place_order(5014, 1004);")

    order_id = scalar("SELECT order_id FROM trade_demo.trade_order WHERE listing_id = 5015")
    if not order_id.isdigit():
        raise AssertionError("结算测试订单编号无效")
    compete("同一订单双会话结算",
            f"SELECT trade_demo.complete_order({order_id}, 'BUYER_CONFIRMED', 1001);",
            f"SELECT trade_demo.complete_order({order_id}, 'BUYER_CONFIRMED', 1001);")

    # 买家在截止前反馈未收到并持有订单锁；自动结算到期后只能等待并最终失败。
    race_id = scalar("SELECT trade_demo.test_seed_paid_order(5016, 8, clock_timestamp())")
    scalar(f"SELECT trade_demo.mark_order_delivered({race_id}, 1002, INTERVAL '5 seconds')")
    feedback = subprocess.Popen(
        common + ["-c", "BEGIN;",
                  "-c", f"SELECT trade_demo.open_order_review({race_id}, 'NOT_RECEIVED', 1001);",
                  "-c", "SELECT pg_sleep(6);", "-c", "COMMIT;"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        encoding="utf-8", errors="replace", creationflags=flags,
    )
    try:
        wait_until_first_holds_lock(feedback, 6)
        deadline = time.monotonic() + 7
        while scalar(f"SELECT CASE WHEN auto_complete_at <= clock_timestamp() THEN 1 ELSE 0 END "
                     f"FROM trade_demo.trade_order WHERE order_id = {race_id}") != "1":
            if time.monotonic() > deadline:
                raise AssertionError("自动完成截止时间未到")
            time.sleep(0.05)
        started = time.monotonic()
        automatic = subprocess.run(
            common + ["-c", f"SELECT trade_demo.complete_order({race_id}, 'AUTO');"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            creationflags=flags, timeout=8,
        )
        waited = time.monotonic() - started
        _, feedback_err = feedback.communicate(timeout=8)
        if feedback.returncode != 0:
            raise AssertionError(f"买家反馈事务失败：{feedback_err}")
        if automatic.returncode == 0 or waited < 0.5:
            raise AssertionError("有效反馈后自动结算未被阻止或未等待订单锁")
        print(f"PASS 反馈先于自动结算: feedback=success, auto=rejected, waited={waited:.2f}s")
    finally:
        if feedback.poll() is None:
            feedback.kill()
            feedback.communicate()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL 并发自测: {exc}", file=sys.stderr)
        sys.exit(1)
