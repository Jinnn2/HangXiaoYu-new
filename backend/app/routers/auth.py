"""注册、登录、个人信息。"""

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from ..db import BusinessError, execute, fetch_all, fetch_one, fetch_value
from ..deps import current_user

router = APIRouter(prefix="/api", tags=["用户"])


class RegisterIn(BaseModel):
    student_no: str = Field(min_length=4, max_length=20)
    display_name: str = Field(min_length=1, max_length=40)
    password: str = Field(min_length=6, max_length=72)


class LoginIn(BaseModel):
    student_no: str
    password: str


class PasswordIn(BaseModel):
    old_password: str
    new_password: str = Field(min_length=6, max_length=72)


class ProfileIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=40)


ME_SQL = "SELECT * FROM hxy.v_user_account_summary WHERE user_id = %s"


@router.post("/auth/register")
def register(body: RegisterIn, request: Request):
    user_id = fetch_value("SELECT hxy.register_user(%s, %s, %s)",
                          (body.student_no, body.display_name, body.password))
    request.session["user_id"] = user_id
    return fetch_one(ME_SQL, (user_id,))


@router.post("/auth/login")
def login(body: LoginIn, request: Request):
    user_id = fetch_value("SELECT hxy.authenticate(%s, %s)", (body.student_no, body.password))
    if user_id is None:
        raise BusinessError("学号或密码错误，或账号已被封禁", 401)
    request.session["user_id"] = user_id
    return fetch_one(ME_SQL, (user_id,))


@router.post("/auth/logout")
def logout(request: Request):
    request.session.clear()
    return {"ok": True}


@router.get("/auth/me")
def me(user=Depends(current_user)):
    return fetch_one(ME_SQL, (user["user_id"],))


@router.put("/me/profile")
def update_profile(body: ProfileIn, user=Depends(current_user)):
    execute("UPDATE hxy.app_user SET display_name = btrim(%s) WHERE user_id = %s",
            (body.display_name, user["user_id"]))
    return fetch_one(ME_SQL, (user["user_id"],))


@router.post("/me/password")
def change_password(body: PasswordIn, user=Depends(current_user)):
    fetch_value("SELECT hxy.change_password(%s, %s, %s)",
                (user["user_id"], body.old_password, body.new_password))
    return {"ok": True}


@router.get("/me/ledger")
def my_ledger(user=Depends(current_user)):
    return fetch_all(
        "SELECT ledger_id, transfer_id, order_id, event_type, occurred_at, delta_points, listing_title "
        "FROM hxy.v_account_statement WHERE user_id = %s "
        "ORDER BY occurred_at DESC, ledger_id DESC LIMIT 200",
        (user["user_id"],),
    )


@router.get("/users/{user_id}")
def public_profile(user_id: int):
    """卖家主页：公开信息、信誉、在售商品。"""
    profile = fetch_one(
        "SELECT u.user_id, u.display_name, u.created_at, r.reputation, r.completed_sales "
        "FROM hxy.app_user u JOIN hxy.v_seller_reputation r USING (user_id) "
        "WHERE u.user_id = %s AND u.status = 'ACTIVE'",
        (user_id,),
    )
    if profile is None:
        raise BusinessError("用户不存在", 404)
    profile["listings"] = fetch_all(
        "SELECT * FROM hxy.v_listing_card WHERE seller_id = %s AND status = 'ON_SALE' "
        "ORDER BY created_at DESC",
        (user_id,),
    )
    return profile
