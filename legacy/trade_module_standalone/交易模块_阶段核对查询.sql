-- 航小鱼交易模块阶段检查：全部为只读 SELECT，可在 pgAdmin 的 Query Tool 运行。
-- 运行库：hangxiaoyu_trade_demo；不需要填写订单编号。
-- 前两项显示业务数据；最后三项用于发现账本/托管/价格不一致。

-- 1. 订单全貌：包括用户、卖家和四个关键时间。
SELECT o.order_id, o.listing_id,
       o.buyer_id, buyer.display_name AS buyer_name,
       l.seller_id, seller.display_name AS seller_name,
       o.price_snapshot_points, o.status,
       o.created_at, o.paid_at, o.delivered_at, o.completed_at,
       o.completion_method
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
JOIN trade_demo.user_stub AS buyer ON buyer.user_id = o.buyer_id
JOIN trade_demo.user_stub AS seller ON seller.user_id = l.seller_id
ORDER BY o.order_id;

-- 2. 每笔付款、结算、退款如何影响各账户。
SELECT t.order_id, t.event_type, t.occurred_at,
       a.owner_type, a.user_id, ledger.delta_points
FROM trade_demo.point_transfer AS t
JOIN trade_demo.balance_ledger AS ledger ON ledger.transfer_id = t.transfer_id
JOIN trade_demo.point_account AS a ON a.account_id = ledger.account_id
ORDER BY t.order_id, t.transfer_id, ledger.ledger_id;

-- 3. 每次转移应恰好有两条流水、增减合计为 0；正常应返回 0 行。
SELECT t.order_id, t.event_type, t.transfer_id,
       COUNT(ledger.ledger_id) AS ledger_rows,
       COALESCE(SUM(ledger.delta_points), 0) AS net_points
FROM trade_demo.point_transfer AS t
LEFT JOIN trade_demo.balance_ledger AS ledger ON ledger.transfer_id = t.transfer_id
GROUP BY t.order_id, t.event_type, t.transfer_id
HAVING COUNT(ledger.ledger_id) <> 2
    OR COALESCE(SUM(ledger.delta_points), 0) <> 0;

-- 4. 托管账户余额应等于所有已付款、尚未结算/退款的订单价格之和。
WITH expected AS (
    SELECT COALESCE(SUM(price_snapshot_points), 0) AS escrow_expected
    FROM trade_demo.trade_order
    WHERE status IN ('PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW')
)
SELECT a.balance_points AS escrow_actual, e.escrow_expected,
       a.balance_points - e.escrow_expected AS difference
FROM trade_demo.point_account AS a CROSS JOIN expected AS e
WHERE a.owner_type = 'PLATFORM_ESCROW';

-- 5. 当前价与最后一次价格历史不一致的商品；正常应返回 0 行。
SELECT l.listing_id, l.current_price_points,
       latest.price_points AS latest_history_price
FROM trade_demo.listing_stub AS l
LEFT JOIN LATERAL (
    SELECT h.price_points
    FROM trade_demo.price_history AS h
    WHERE h.listing_id = l.listing_id
    ORDER BY h.changed_at DESC, h.history_id DESC
    LIMIT 1
) AS latest ON TRUE
WHERE l.current_price_points IS DISTINCT FROM latest.price_points;

-- 6. 卖家信誉分演示口径：初始 80，按已记录事件计算，范围 0～100。
SELECT u.user_id, u.display_name,
       LEAST(100, GREATEST(0, 80 + COALESCE(SUM(s.delta_score), 0)))
           AS seller_reputation
FROM trade_demo.user_stub AS u
LEFT JOIN trade_demo.score_event AS s
  ON s.user_id = u.user_id AND s.score_type = 'SELLER_REPUTATION'
WHERE EXISTS (
    SELECT 1 FROM trade_demo.listing_stub AS l WHERE l.seller_id = u.user_id
)
GROUP BY u.user_id, u.display_name
ORDER BY u.user_id;
