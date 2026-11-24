"""数据库访问层。

本项目对数据库的全部操作都是手写的原生 SQL 字符串，经 psycopg 以参数绑定（%s 占位符）方式执行；
没有 ORM、没有查询构造器，也不会把用户输入拼接进 SQL 文本。
psycopg 在这里只承担"建立连接、发送 SQL、取回结果行"的驱动职责。
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterator

from psycopg import Connection, errors
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from . import config

pool = ConnectionPool(
    config.DATABASE_URL,
    min_size=1,
    max_size=10,
    open=False,
    kwargs={"row_factory": dict_row, "options": "-c timezone=Asia/Shanghai"},
)


@contextmanager
def transaction() -> Iterator[Connection]:
    """取一个连接；代码块正常结束则 COMMIT，抛异常则 ROLLBACK。"""
    with pool.connection() as conn:
        yield conn


def fetch_all(sql: str, params: tuple | dict = ()) -> list[dict[str, Any]]:
    with transaction() as conn:
        return conn.execute(sql, params).fetchall()


def fetch_one(sql: str, params: tuple | dict = ()) -> dict[str, Any] | None:
    with transaction() as conn:
        return conn.execute(sql, params).fetchone()


def fetch_value(sql: str, params: tuple | dict = ()) -> Any:
    row = fetch_one(sql, params)
    return None if row is None else next(iter(row.values()))


def execute(sql: str, params: tuple | dict = ()) -> int:
    with transaction() as conn:
        return conn.execute(sql, params).rowcount


class BusinessError(Exception):
    """可以直接展示给用户的业务错误。"""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


# 约束名 → 用户能看懂的提示
CONSTRAINT_MESSAGES = {
    "app_user_student_no_key": "该学号已注册",
    "app_user_student_no_format": "学号只能包含 4~20 位字母或数字",
    "app_user_name_not_blank": "昵称不能为空",
    "listing_title_not_blank": "商品标题不能为空",
    "listing_condition_check": "成色必须在 1~5 之间",
    "listing_price_check": "价格必须是正整数",
    "listing_original_price_check": "原价必须是正整数",
    "favorite_pkey": "已经收藏过了",
    "trade_order_one_active_per_listing": "商品已被其他订单占用",
    "point_transfer_one_terminal_per_order": "该订单已结算或已退款",
    "order_review_one_open_per_order": "该订单已有正在处理的核实",
    "valuation_original_check": "原价必须是正整数",
}


def to_business_error(exc: Exception) -> BusinessError | None:
    """把数据库抛出的错误翻译成业务错误；不认识的错误返回 None（按 500 处理）。"""
    if isinstance(exc, errors.RaiseException):  # 存储过程里 RAISE EXCEPTION 的业务错误
        return BusinessError(exc.diag.message_primary or "操作失败")
    if isinstance(exc, errors.IntegrityError):  # 违反 UNIQUE / CHECK / FOREIGN KEY 等约束
        name = exc.diag.constraint_name
        if name in CONSTRAINT_MESSAGES:
            return BusinessError(CONSTRAINT_MESSAGES[name])
        if exc.diag.sqlstate == "23514" and exc.diag.message_primary:  # 触发器抛出的完整性错误
            return BusinessError(exc.diag.message_primary)
        if isinstance(exc, errors.ForeignKeyViolation):
            return BusinessError("引用的数据不存在或仍被其他记录使用")
        return BusinessError("数据不符合约束：" + (name or exc.diag.message_primary or ""))
    if isinstance(exc, (errors.InvalidTextRepresentation, errors.NumericValueOutOfRange)):
        return BusinessError("参数格式不正确")
    return None
