"""看板：个人看板与管理后台看板。全部数据来自数据库视图与统计函数。"""

from fastapi import APIRouter, Depends

from ..db import fetch_all, fetch_one
from ..deps import admin_user, current_user

router = APIRouter(prefix="/api", tags=["看板"])


@router.get("/me/dashboard")
def my_dashboard(user=Depends(current_user)):
    uid = user["user_id"]
    return {
        "summary": fetch_one("SELECT * FROM hxy.v_user_account_summary WHERE user_id = %s", (uid,)),
        "stats": fetch_one("SELECT * FROM hxy.user_trade_stats(%s)", (uid,)),
        "flow": fetch_all("SELECT * FROM hxy.user_daily_flow(%s, 30)", (uid,)),
        "todos": fetch_all(
            "SELECT order_id, listing_title, image_url, category_name, price_snapshot_points, status, "
            "       action, due_at, buyer_name, seller_name, clock_timestamp() AS server_time "
            "FROM hxy.v_order_todo WHERE actor_id = %s ORDER BY due_at NULLS LAST", (uid,)),
        "listing_status": fetch_all(
            "SELECT status, COUNT(*) AS n FROM hxy.listing WHERE seller_id = %s GROUP BY status", (uid,)),
        "relist_buffer": fetch_all(
            "SELECT listing_id, title FROM hxy.listing WHERE seller_id = %s AND status = 'RELIST_BUFFER'", (uid,)),
        "recent": fetch_all(
            "SELECT ledger_id, order_id, event_type, occurred_at, delta_points, listing_title "
            "FROM hxy.v_account_statement WHERE user_id = %s ORDER BY occurred_at DESC, ledger_id DESC LIMIT 6",
            (uid,)),
    }


@router.get("/admin/dashboard")
def admin_dashboard(admin=Depends(admin_user)):
    return {
        "stats": fetch_one("SELECT * FROM hxy.v_platform_stats"),
        "daily": fetch_all("SELECT * FROM hxy.platform_daily_activity(14)"),
        "order_status": fetch_all("SELECT status, COUNT(*) AS n FROM hxy.trade_order GROUP BY status"),
        "categories": fetch_all(
            "SELECT c.category_id, c.name, c.deals_180d, c.on_sale_count, "
            "       COALESCE(SUM(o.price_snapshot_points), 0) AS volume_180d "
            "FROM hxy.v_category_market c "
            "LEFT JOIN hxy.listing l ON l.category_id = c.category_id "
            "LEFT JOIN hxy.trade_order o ON o.listing_id = l.listing_id AND o.status = 'COMPLETED' "
            "      AND o.completed_at >= clock_timestamp() - INTERVAL '180 days' "
            "GROUP BY c.category_id, c.name, c.deals_180d, c.on_sale_count ORDER BY volume_180d DESC"),
        "top_sellers": fetch_all("SELECT * FROM hxy.v_top_sellers ORDER BY volume DESC, deals DESC LIMIT 5"),
        # 需要关注：12 小时内到交付期限的待交付订单、5 分钟内到期的待付款订单
        "attention": fetch_all(
            "SELECT order_id, listing_title, buyer_name, seller_name, status, "
            "       CASE status WHEN 'PENDING_DELIVERY' THEN paid_at + INTERVAL '48 hours' "
            "                   ELSE payment_deadline_at END AS due_at, clock_timestamp() AS server_time "
            "FROM hxy.v_order_details "
            "WHERE (status = 'PENDING_DELIVERY' AND paid_at + INTERVAL '48 hours' <= clock_timestamp() + INTERVAL '12 hours') "
            "   OR (status = 'PENDING_PAYMENT') "
            "ORDER BY due_at LIMIT 8"),
        "reviews": fetch_one("SELECT COUNT(*) AS n, min(opened_at) AS oldest FROM hxy.v_open_reviews"),
    }
