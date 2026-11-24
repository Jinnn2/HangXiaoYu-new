"""管理员：平台统计、异常核实、用户与商品管理、手动运行定时任务。"""

from typing import Literal, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..db import fetch_all, fetch_one, fetch_value
from ..deps import admin_user

router = APIRouter(prefix="/api/admin", tags=["管理员"])


class ResolveIn(BaseModel):
    decision: Literal["CANCEL", "CONTINUE"]
    verified_delivery_late: bool = False


class StatusIn(BaseModel):
    status: Literal["ACTIVE", "BANNED"]


class BlockIn(BaseModel):
    blocked: bool


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=20)
    sort_order: int = 0


@router.get("/stats")
def stats(admin=Depends(admin_user)):
    return fetch_one("SELECT * FROM hxy.v_platform_stats")


@router.get("/reviews")
def open_reviews(admin=Depends(admin_user)):
    return fetch_all("SELECT * FROM hxy.v_open_reviews ORDER BY opened_at")


@router.post("/reviews/{review_id}/resolve")
def resolve(review_id: int, body: ResolveIn, admin=Depends(admin_user)):
    order_id = fetch_value("SELECT hxy.resolve_order_review(%s, %s, %s, %s)",
                           (review_id, admin["user_id"], body.decision, body.verified_delivery_late))
    return {"order_id": order_id}


@router.get("/users")
def users(q: Optional[str] = None, admin=Depends(admin_user)):
    return fetch_all(
        "SELECT user_id, student_no, display_name, role, status, created_at, spendable_points, "
        "seller_reputation, completed_sales FROM hxy.v_user_account_summary "
        "WHERE %(q)s::text IS NULL OR student_no ILIKE '%%' || %(q)s || '%%' "
        "   OR display_name ILIKE '%%' || %(q)s || '%%' "
        "ORDER BY user_id", {"q": q or None})


@router.post("/users/{user_id}/status")
def set_status(user_id: int, body: StatusIn, admin=Depends(admin_user)):
    fetch_value("SELECT hxy.set_user_status(%s, %s, %s)", (admin["user_id"], user_id, body.status))
    return {"ok": True}


@router.get("/listings")
def all_listings(q: Optional[str] = None, admin=Depends(admin_user)):
    return fetch_all(
        "SELECT * FROM hxy.v_listing_card WHERE %(q)s::text IS NULL OR title ILIKE '%%' || %(q)s || '%%' "
        "ORDER BY listing_id DESC LIMIT 200", {"q": q or None})


@router.post("/listings/{listing_id}/relist-blocked")
def block_relist(listing_id: int, body: BlockIn, admin=Depends(admin_user)):
    fetch_value("SELECT hxy.set_relist_blocked(%s, %s, %s)", (admin["user_id"], listing_id, body.blocked))
    return {"ok": True}


@router.post("/categories")
def add_category(body: CategoryIn, admin=Depends(admin_user)):
    return fetch_one("INSERT INTO hxy.category (name, sort_order) VALUES (btrim(%s), %s) "
                     "RETURNING category_id, name", (body.name, body.sort_order))


@router.post("/tasks/run")
def run_tasks(admin=Depends(admin_user)):
    return fetch_one("SELECT * FROM hxy.run_scheduled_tasks()")
