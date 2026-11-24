-- 航小鱼交易模块：下单后进入待付款（独立演示库草案）
-- 运行环境：hangxiaoyu_trade_demo 数据库；首次演示数据商品 5001、买家 1001。
-- 一次执行整份脚本。商品只有在 ON_SALE 且买家不是卖家时才会被预留。
-- 若商品未符合条件，reserved_listing 为零行，订单也不会插入。
-- 本步骤不扣除买家积分；付款事务另行实现。
-- 这里只写入 5 分钟截止时间；自动取消超时订单和释放商品将由后续 SQL 实现。

BEGIN;

WITH reserved_listing AS (
    UPDATE trade_demo.listing_stub
    SET status = 'PAYMENT_RESERVED'
    WHERE listing_id = 5001
      AND status = 'ON_SALE'
      AND seller_id <> 1001
    RETURNING listing_id, current_price_points
)
INSERT INTO trade_demo.trade_order
    (listing_id, buyer_id, price_snapshot_points, status,
     created_at, payment_deadline_at)
SELECT listing_id, 1001, current_price_points, 'PENDING_PAYMENT',
       CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '5 minutes'
FROM reserved_listing;

COMMIT;

-- 核对：商品状态应为 PAYMENT_RESERVED。
SELECT listing_id, status
FROM trade_demo.listing_stub
WHERE listing_id = 5001;

-- 核对当前待付款订单：如果商品已经处于交易中，这里应返回零行，
-- 不能将上一笔已付款订单误认为本次新建的订单。
SELECT order_id, listing_id, buyer_id, price_snapshot_points,
       status, created_at, payment_deadline_at
FROM trade_demo.trade_order
WHERE listing_id = 5001 AND buyer_id = 1001 AND status = 'PENDING_PAYMENT'
ORDER BY order_id DESC
LIMIT 1;
