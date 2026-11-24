-- 航小鱼交易模块：处理已超过 5 分钟付款截止时间的待付款订单。
-- 运行于 hangxiaoyu_trade_demo 独立演示数据库。
-- 未付款超时订单保留为 PAYMENT_EXPIRED 历史记录；对应商品重新在售。
-- 本文件是手动执行的一次清理；定时自动运行尚未实现。
-- 2026-11-13 手动演示核对：用户在 pgAdmin 反馈订单 1 为 PAYMENT_EXPIRED、商品 5001 为 ON_SALE。
-- 该结果只覆盖这笔演示订单；并发付款和定时调度仍待验证。
-- 只有已超时且仍待付款的订单会被处理；已付款订单和交易中的商品保持原状。

BEGIN;

WITH expired_orders AS (
    UPDATE trade_demo.trade_order
    SET status = 'PAYMENT_EXPIRED'
    WHERE status = 'PENDING_PAYMENT'
      AND payment_deadline_at <= clock_timestamp()
    RETURNING order_id, listing_id
)
UPDATE trade_demo.listing_stub AS listing
SET status = 'ON_SALE'
FROM expired_orders AS expired
WHERE listing.listing_id = expired.listing_id
  AND listing.status = 'PAYMENT_RESERVED';

COMMIT;

-- 查看最新订单的实际状态。若已付款，这里会是 PENDING_DELIVERY。
SELECT order_id, listing_id, buyer_id, status, payment_deadline_at
FROM trade_demo.trade_order
WHERE listing_id = 5001 AND buyer_id = 1001
ORDER BY order_id DESC
LIMIT 1;

-- 查看商品的实际状态。若订单已付款，这里会是 TRADING。
SELECT listing_id, status
FROM trade_demo.listing_stub
WHERE listing_id = 5001;

-- 清理后，当前仍超时待付款的订单应为 0；这不表示本次一定修改了某笔订单。
SELECT COUNT(*) AS overdue_pending_orders
FROM trade_demo.trade_order
WHERE status = 'PENDING_PAYMENT'
  AND payment_deadline_at <= clock_timestamp();
