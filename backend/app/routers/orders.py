"""订单：下单、付款、取消、交付、确认收货、申请核实。

业务规则与并发控制全部在数据库存储过程里完成，这里只负责：
确认登录身份 → 用参数绑定调用对应函数 → 返回最新的订单数据。
"""

from datetime import timedelta
from typing import Literal, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .. import config
from ..db import BusinessError, fetch_all, fetch_one, fetch_value
from ..deps import current_user

router = APIRouter(prefix="/api", tags=["订单"])


class PlaceOrderIn(BaseModel):
    listing_id: int
    expected_price: Optional[int] = None


ORDER_SQL = "SELECT *, clock_timestamp() AS server_time FROM hxy.v_order_details WHERE order_id = %s"


def load_order(order_id: int, user: dict) -> dict:
    order = fetch_one(ORDER_SQL, (order_id,))
    if order is None:
        raise BusinessError("订单不存在", 404)
    if user["user_id"] not in (order["buyer_id"], order["seller_id"]) and user["role"] != "ADMIN":
        raise BusinessError("无权查看该订单", 403)
    order["my_role"] = ("buyer" if user["user_id"] == order["buyer_id"]
                        else "seller" if user["user_id"] == order["seller_id"] else "admin")
    order["reviews"] = fetch_all(
        "SELECT review_id, reason, previous_status, opened_at, decision, resolved_at "
        "FROM hxy.order_review WHERE order_id = %s ORDER BY review_id", (order_id,))
    order["transfers"] = fetch_all(
        "SELECT t.event_type, t.occurred_at, b.delta_points, a.owner_type, a.user_id "
        "FROM hxy.point_transfer t JOIN hxy.balance_ledger b USING (transfer_id) "
        "JOIN hxy.point_account a USING (account_id) WHERE t.order_id = %s "
        "ORDER BY t.transfer_id, b.ledger_id", (order_id,))
    return order


@router.post("/orders")
def place_order(body: PlaceOrderIn, user=Depends(current_user)):
    order_id = fetch_value("SELECT hxy.place_order(%s, %s, %s)",
                           (body.listing_id, user["user_id"], body.expected_price))
    return load_order(order_id, user)


@router.get("/me/orders")
def my_orders(role: Literal["buyer", "seller"] = "buyer", user=Depends(current_user)):
    column = {"buyer": "buyer_id", "seller": "seller_id"}[role]  # 白名单选择列名，不拼接用户输入
    return fetch_all(
        f"SELECT *, clock_timestamp() AS server_time FROM hxy.v_order_details "
        f"WHERE {column} = %s ORDER BY order_id DESC",
        (user["user_id"],),
    )


@router.get("/orders/{order_id}")
def order_detail(order_id: int, user=Depends(current_user)):
    return load_order(order_id, user)


@router.post("/orders/{order_id}/pay")
def pay(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.pay_order(%s, %s)", (order_id, user["user_id"]))
    return load_order(order_id, user)


@router.post("/orders/{order_id}/cancel")
def cancel_unpaid(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.cancel_unpaid_order(%s, %s)", (order_id, user["user_id"]))
    return load_order(order_id, user)


@router.post("/orders/{order_id}/deliver")
def deliver(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.mark_order_delivered(%s, %s, %s)",
                (order_id, user["user_id"], timedelta(seconds=config.AUTO_COMPLETE_SECONDS)))
    return load_order(order_id, user)


@router.post("/orders/{order_id}/confirm")
def confirm_receipt(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.complete_order(%s, 'BUYER_CONFIRMED', %s)", (order_id, user["user_id"]))
    return load_order(order_id, user)


@router.post("/orders/{order_id}/request-cancel")
def request_cancel(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.open_order_review(%s, 'BUYER_CANCEL_REQUEST', %s)", (order_id, user["user_id"]))
    return load_order(order_id, user)


@router.post("/orders/{order_id}/not-received")
def not_received(order_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.open_order_review(%s, 'NOT_RECEIVED', %s)", (order_id, user["user_id"]))
    return load_order(order_id, user)
