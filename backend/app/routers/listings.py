"""商品、分类、收藏。"""

from typing import Literal, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from ..db import BusinessError, execute, fetch_all, fetch_one, fetch_value
from ..deps import current_user, optional_user

router = APIRouter(prefix="/api", tags=["商品"])


class ListingIn(BaseModel):
    category_id: int
    title: str = Field(min_length=1, max_length=60)
    description: str = Field(default="", max_length=2000)
    condition_level: int = Field(ge=1, le=5)
    original_price_points: Optional[int] = Field(default=None, gt=0)
    current_price_points: int = Field(gt=0)
    image_url: Optional[str] = Field(default=None, max_length=500)


class ListingUpdateIn(BaseModel):
    category_id: int
    title: str = Field(min_length=1, max_length=60)
    description: str = Field(default="", max_length=2000)
    condition_level: int = Field(ge=1, le=5)
    original_price_points: Optional[int] = Field(default=None, gt=0)
    image_url: Optional[str] = Field(default=None, max_length=500)


class RepriceIn(BaseModel):
    price: int = Field(gt=0)


@router.get("/categories")
def categories():
    return fetch_all("SELECT category_id, name FROM hxy.category ORDER BY sort_order, category_id")


@router.get("/market/categories")
def category_market():
    return fetch_all("SELECT * FROM hxy.v_category_market ORDER BY category_id")


# 一条固定的 SQL 覆盖全部筛选组合：参数为 NULL 时对应条件不起作用，排序由 CASE 选择。
LISTING_SEARCH_SQL = """
SELECT *, COUNT(*) OVER () AS total
  FROM hxy.v_listing_card
 WHERE status = 'ON_SALE'
   AND (%(q)s::text IS NULL OR title ILIKE '%%' || %(q)s || '%%' OR description ILIKE '%%' || %(q)s || '%%')
   AND (%(category_id)s::int IS NULL OR category_id = %(category_id)s)
   AND (%(min_price)s::bigint IS NULL OR current_price_points >= %(min_price)s)
   AND (%(max_price)s::bigint IS NULL OR current_price_points <= %(max_price)s)
 ORDER BY
   CASE WHEN %(sort)s = 'price_asc'  THEN current_price_points END ASC,
   CASE WHEN %(sort)s = 'price_desc' THEN current_price_points END DESC,
   CASE WHEN %(sort)s = 'popular'    THEN favorite_count END DESC,
   created_at DESC, listing_id DESC
 LIMIT %(limit)s OFFSET %(offset)s
"""


@router.get("/listings")
def search_listings(
    q: Optional[str] = None,
    category_id: Optional[int] = None,
    min_price: Optional[int] = None,
    max_price: Optional[int] = None,
    sort: Literal["new", "price_asc", "price_desc", "popular"] = "new",
    page: int = Query(1, ge=1),
    page_size: int = Query(24, ge=1, le=60),
):
    rows = fetch_all(LISTING_SEARCH_SQL, {
        "q": q.strip() if q and q.strip() else None,
        "category_id": category_id, "min_price": min_price, "max_price": max_price,
        "sort": sort, "limit": page_size, "offset": (page - 1) * page_size,
    })
    total = rows[0]["total"] if rows else 0
    for r in rows:
        r.pop("total")
    return {"items": rows, "total": total, "page": page, "page_size": page_size}


@router.get("/listings/{listing_id}")
def listing_detail(listing_id: int, user=Depends(optional_user)):
    item = fetch_one("SELECT * FROM hxy.v_listing_card WHERE listing_id = %s", (listing_id,))
    if item is None:
        raise BusinessError("商品不存在", 404)
    item["price_history"] = fetch_all(
        "SELECT history_id, price_points, change_type, changed_at FROM hxy.price_history "
        "WHERE listing_id = %s ORDER BY changed_at, history_id",
        (listing_id,),
    )
    item["is_favorite"] = False
    item["my_active_order_id"] = None
    if user:
        item["is_favorite"] = fetch_value(
            "SELECT EXISTS (SELECT 1 FROM hxy.favorite WHERE user_id = %s AND listing_id = %s)",
            (user["user_id"], listing_id))
        item["my_active_order_id"] = fetch_value(
            "SELECT order_id FROM hxy.trade_order WHERE listing_id = %s AND buyer_id = %s "
            "AND status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW')",
            (listing_id, user["user_id"]))
    return item


@router.post("/listings")
def create_listing(body: ListingIn, user=Depends(current_user)):
    listing_id = fetch_value(
        "SELECT hxy.create_listing(%s, %s, %s, %s, %s::smallint, %s, %s, %s)",
        (user["user_id"], body.category_id, body.title, body.description, body.condition_level,
         body.original_price_points, body.current_price_points, body.image_url),
    )
    return listing_detail(listing_id, user)


@router.put("/listings/{listing_id}")
def update_listing(listing_id: int, body: ListingUpdateIn, user=Depends(current_user)):
    fetch_value(
        "SELECT hxy.update_listing_info(%s, %s, %s, %s, %s, %s::smallint, %s, %s)",
        (listing_id, user["user_id"], body.category_id, body.title, body.description,
         body.condition_level, body.original_price_points, body.image_url),
    )
    return listing_detail(listing_id, user)


@router.post("/listings/{listing_id}/reprice")
def reprice(listing_id: int, body: RepriceIn, user=Depends(current_user)):
    fetch_value("SELECT hxy.reprice_listing(%s, %s, %s)", (listing_id, user["user_id"], body.price))
    return listing_detail(listing_id, user)


@router.post("/listings/{listing_id}/off-shelf")
def off_shelf(listing_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.take_off_shelf(%s, %s)", (listing_id, user["user_id"]))
    return listing_detail(listing_id, user)


@router.post("/listings/{listing_id}/on-shelf")
def on_shelf(listing_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.put_on_shelf(%s, %s)", (listing_id, user["user_id"]))
    return listing_detail(listing_id, user)


@router.delete("/listings/{listing_id}")
def delete_listing(listing_id: int, user=Depends(current_user)):
    fetch_value("SELECT hxy.delete_listing(%s, %s)", (listing_id, user["user_id"]))
    return {"ok": True}


@router.get("/me/listings")
def my_listings(user=Depends(current_user)):
    return fetch_all(
        "SELECT c.*, "
        "  (SELECT max(o.canceled_at) FROM hxy.trade_order o WHERE o.listing_id = c.listing_id) "
        "    AS last_canceled_at "
        "FROM hxy.v_listing_card c WHERE c.seller_id = %s ORDER BY c.updated_at DESC",
        (user["user_id"],),
    )


# ---------------------------------------------------------------- 收藏（直接写 INSERT / DELETE）
@router.get("/me/favorites")
def my_favorites(user=Depends(current_user)):
    return fetch_all(
        "SELECT c.*, f.created_at AS favorited_at FROM hxy.favorite f "
        "JOIN hxy.v_listing_card c ON c.listing_id = f.listing_id "
        "WHERE f.user_id = %s ORDER BY f.created_at DESC",
        (user["user_id"],),
    )


@router.put("/listings/{listing_id}/favorite")
def add_favorite(listing_id: int, user=Depends(current_user)):
    execute("INSERT INTO hxy.favorite (user_id, listing_id) VALUES (%s, %s) "
            "ON CONFLICT (user_id, listing_id) DO NOTHING", (user["user_id"], listing_id))
    return {"is_favorite": True}


@router.delete("/listings/{listing_id}/favorite")
def remove_favorite(listing_id: int, user=Depends(current_user)):
    execute("DELETE FROM hxy.favorite WHERE user_id = %s AND listing_id = %s",
            (user["user_id"], listing_id))
    return {"is_favorite": False}
