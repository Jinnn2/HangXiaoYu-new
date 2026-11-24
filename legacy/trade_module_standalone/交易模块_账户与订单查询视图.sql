-- 航小鱼交易模块：账户页与交易记录页可使用的原生 PostgreSQL 只读视图。
-- 独立演示库的接口草案；小组正式 User、Listing 表确定后需调整。

CREATE OR REPLACE VIEW trade_demo.v_order_details AS
SELECT o.order_id, o.listing_id, o.buyer_id,
       buyer.display_name AS buyer_name,
       l.seller_id, seller.display_name AS seller_name,
       o.price_snapshot_points, o.status,
       o.created_at, o.payment_deadline_at, o.paid_at,
       o.delivered_at, o.auto_complete_at, o.completed_at,
       o.completion_method, o.canceled_at, o.cancel_reason
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
JOIN trade_demo.user_stub AS buyer ON buyer.user_id = o.buyer_id
JOIN trade_demo.user_stub AS seller ON seller.user_id = l.seller_id;

CREATE OR REPLACE VIEW trade_demo.v_account_statement AS
SELECT a.user_id, a.account_id, t.order_id, t.event_type,
       t.occurred_at, ledger.ledger_id, ledger.delta_points
FROM trade_demo.point_account AS a
JOIN trade_demo.balance_ledger AS ledger ON ledger.account_id = a.account_id
JOIN trade_demo.point_transfer AS t ON t.transfer_id = ledger.transfer_id
WHERE a.owner_type = 'USER';

CREATE OR REPLACE VIEW trade_demo.v_user_account_summary AS
SELECT u.user_id, u.display_name,
       a.balance_points AS spendable_points,
       COALESCE((
           SELECT SUM(s.delta_score) FROM trade_demo.score_event AS s
           WHERE s.user_id = u.user_id
             AND s.score_type = 'BUYER_REWARD'
       ), 0) AS buyer_reward_points,
       CASE WHEN EXISTS (
           SELECT 1 FROM trade_demo.listing_stub AS l WHERE l.seller_id = u.user_id
       ) THEN LEAST(100, GREATEST(0, 80 + COALESCE((
           SELECT SUM(s.delta_score) FROM trade_demo.score_event AS s
           WHERE s.user_id = u.user_id
             AND s.score_type = 'SELLER_REPUTATION'
       ), 0))) END AS seller_reputation
FROM trade_demo.user_stub AS u
LEFT JOIN trade_demo.point_account AS a
  ON a.owner_type = 'USER' AND a.user_id = u.user_id;

-- 页面查询示例：
-- SELECT * FROM trade_demo.v_user_account_summary WHERE user_id = 1001;
-- SELECT * FROM trade_demo.v_account_statement
--  WHERE user_id = 1001 ORDER BY occurred_at DESC, ledger_id DESC;
-- SELECT * FROM trade_demo.v_order_details
--  WHERE buyer_id = 1001 OR seller_id = 1001 ORDER BY order_id DESC;
