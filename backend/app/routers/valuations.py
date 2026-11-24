"""智能估价。"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..db import BusinessError, execute, fetch_all, fetch_one, fetch_value
from ..deps import current_user

router = APIRouter(prefix="/api", tags=["估价"])


class EstimateIn(BaseModel):
    category_id: int
    condition_level: int = Field(ge=1, le=5)
    original_price: int = Field(gt=0, le=10_000_000)


class ValuationIn(EstimateIn):
    item_name: str = Field(min_length=1, max_length=60)


VALUATION_COLUMNS = (
    "v.valuation_id, v.category_id, c.name AS category_name, v.item_name, v.condition_level, "
    "v.original_price_points, v.suggested_price_points, v.low_price_points, v.high_price_points, "
    "v.sample_count, v.created_at"
)


@router.post("/valuations/estimate")
def estimate(body: EstimateIn):
    """只计算不保存，发布商品时实时参考。"""
    return fetch_one("SELECT * FROM hxy.estimate_price(%s, %s::smallint, %s)",
                     (body.category_id, body.condition_level, body.original_price))


@router.post("/valuations")
def create_valuation(body: ValuationIn, user=Depends(current_user)):
    valuation_id = fetch_value(
        "SELECT hxy.create_valuation(%s, %s, %s, %s::smallint, %s)",
        (user["user_id"], body.category_id, body.item_name, body.condition_level, body.original_price))
    row = fetch_one(f"SELECT {VALUATION_COLUMNS} FROM hxy.valuation v "
                    "JOIN hxy.category c USING (category_id) WHERE v.valuation_id = %s", (valuation_id,))
    row.update(fetch_one("SELECT market_ratio FROM hxy.estimate_price(%s, %s::smallint, %s)",
                         (body.category_id, body.condition_level, body.original_price)))
    return row


@router.get("/me/valuations")
def my_valuations(user=Depends(current_user)):
    return fetch_all(f"SELECT {VALUATION_COLUMNS} FROM hxy.valuation v "
                     "JOIN hxy.category c USING (category_id) "
                     "WHERE v.requester_id = %s ORDER BY v.created_at DESC", (user["user_id"],))


@router.delete("/valuations/{valuation_id}")
def delete_valuation(valuation_id: int, user=Depends(current_user)):
    deleted = execute("DELETE FROM hxy.valuation WHERE valuation_id = %s AND requester_id = %s",
                      (valuation_id, user["user_id"]))
    if deleted == 0:
        raise BusinessError("估价记录不存在", 404)
    return {"ok": True}
