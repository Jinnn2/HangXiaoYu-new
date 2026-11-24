"""登录会话。会话只在签名 Cookie 中保存 user_id；每次请求都回数据库确认账号仍然有效。"""

from __future__ import annotations

from typing import Any

from fastapi import Depends, Request

from .db import BusinessError, fetch_one


def current_user(request: Request) -> dict[str, Any]:
    user_id = request.session.get("user_id")
    if not user_id:
        raise BusinessError("请先登录", 401)
    user = fetch_one(
        "SELECT user_id, student_no, display_name, role FROM hxy.app_user "
        "WHERE user_id = %s AND status = 'ACTIVE'",
        (user_id,),
    )
    if user is None:
        request.session.clear()
        raise BusinessError("登录已失效或账号被封禁", 401)
    return user


def optional_user(request: Request) -> dict[str, Any] | None:
    try:
        return current_user(request)
    except BusinessError:
        return None


def admin_user(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
    if user["role"] != "ADMIN":
        raise BusinessError("需要管理员权限", 403)
    return user
