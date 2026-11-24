-- 航小鱼：视图（外模式）—— 页面只读查询使用；后端按登录用户再加 WHERE 条件。

-- 卖家信誉：初始 80，范围 0~100。score_event 中记录的是截断后的实际变动量。
CREATE OR REPLACE VIEW hxy.v_seller_reputation AS
SELECT u.user_id,
       LEAST(100, GREATEST(0, 80 + COALESCE(SUM(s.delta_score), 0)))::INTEGER AS reputation,
       COUNT(s.*) FILTER (WHERE s.reason = 'COMPLETION') AS completed_sales
  FROM hxy.app_user u
  LEFT JOIN hxy.score_event s ON s.user_id = u.user_id AND s.score_type = 'SELLER_REPUTATION'
 GROUP BY u.user_id;

-- 商品卡片 / 详情。
CREATE OR REPLACE VIEW hxy.v_listing_card AS
SELECT l.listing_id, l.title, l.description, l.condition_level,
       l.original_price_points, l.current_price_points, l.image_url,
       l.status, l.relist_blocked, l.created_at, l.updated_at,
       l.category_id, c.name AS category_name,
       l.seller_id, u.display_name AS seller_name, r.reputation AS seller_reputation,
       (SELECT COUNT(*) FROM hxy.favorite f WHERE f.listing_id = l.listing_id) AS favorite_count
  FROM hxy.listing l
  JOIN hxy.category c ON c.category_id = l.category_id
  JOIN hxy.app_user u ON u.user_id = l.seller_id
  JOIN hxy.v_seller_reputation r ON r.user_id = l.seller_id;

-- 订单详情（买卖双方共用）。
CREATE OR REPLACE VIEW hxy.v_order_details AS
SELECT o.order_id, o.listing_id, l.title AS listing_title, l.image_url, c.name AS category_name,
       o.buyer_id, buyer.display_name AS buyer_name,
       l.seller_id, seller.display_name AS seller_name,
       o.price_snapshot_points, o.status,
       o.created_at, o.payment_deadline_at, o.paid_at,
       o.delivered_at, o.auto_complete_at, o.completed_at,
       o.completion_method, o.canceled_at, o.cancel_reason,
       (SELECT r.review_id FROM hxy.order_review r
         WHERE r.order_id = o.order_id AND r.resolved_at IS NULL) AS open_review_id,
       (SELECT r.reason FROM hxy.order_review r
         WHERE r.order_id = o.order_id AND r.resolved_at IS NULL) AS open_review_reason
  FROM hxy.trade_order o
  JOIN hxy.listing l ON l.listing_id = o.listing_id
  JOIN hxy.category c ON c.category_id = l.category_id
  JOIN hxy.app_user buyer ON buyer.user_id = o.buyer_id
  JOIN hxy.app_user seller ON seller.user_id = l.seller_id;

-- 用户积分流水。
CREATE OR REPLACE VIEW hxy.v_account_statement AS
SELECT a.user_id, b.ledger_id, t.transfer_id, t.order_id, t.event_type,
       t.occurred_at, b.delta_points, l.title AS listing_title
  FROM hxy.point_account a
  JOIN hxy.balance_ledger b ON b.account_id = a.account_id
  JOIN hxy.point_transfer t ON t.transfer_id = b.transfer_id
  LEFT JOIN hxy.trade_order o ON o.order_id = t.order_id
  LEFT JOIN hxy.listing l ON l.listing_id = o.listing_id
 WHERE a.owner_type = 'USER';

-- 账户汇总：可用积分、托管中、买家奖励（已生效 / 待生效）、卖家信誉。
CREATE OR REPLACE VIEW hxy.v_user_account_summary AS
SELECT u.user_id, u.student_no, u.display_name, u.role, u.status, u.created_at,
       a.balance_points AS spendable_points,
       COALESCE((SELECT SUM(o.price_snapshot_points) FROM hxy.trade_order o
                  WHERE o.buyer_id = u.user_id
                    AND o.status IN ('PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW')), 0)
           AS escrow_points,
       COALESCE((SELECT SUM(s.delta_score) FROM hxy.score_event s
                  WHERE s.user_id = u.user_id AND s.score_type = 'BUYER_REWARD'), 0)
           AS buyer_reward_points,
       (SELECT COUNT(*) FROM hxy.trade_order o
         WHERE o.buyer_id = u.user_id
           AND o.status IN ('PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW'))
           AS pending_reward_points,
       r.reputation AS seller_reputation,
       r.completed_sales
  FROM hxy.app_user u
  JOIN hxy.point_account a ON a.owner_type = 'USER' AND a.user_id = u.user_id
  JOIN hxy.v_seller_reputation r ON r.user_id = u.user_id;

-- 管理员：待处理核实单。
CREATE OR REPLACE VIEW hxy.v_open_reviews AS
SELECT r.review_id, r.reason, r.previous_status, r.opened_at,
       d.order_id, d.listing_title, d.price_snapshot_points,
       d.buyer_id, d.buyer_name, d.seller_id, d.seller_name,
       d.paid_at, d.delivered_at, d.auto_complete_at,
       (d.paid_at + INTERVAL '48 hours' <= clock_timestamp()
        AND (d.delivered_at IS NULL OR d.delivered_at >= d.paid_at + INTERVAL '48 hours'))
           AS delivery_late_evidence
  FROM hxy.order_review r
  JOIN hxy.v_order_details d ON d.order_id = r.order_id
 WHERE r.resolved_at IS NULL;

-- 分类行情：近 180 天成交笔数、平均成交价、平均成交折扣率。
CREATE OR REPLACE VIEW hxy.v_category_market AS
SELECT c.category_id, c.name,
       COUNT(o.order_id) AS deals_180d,
       round(AVG(o.price_snapshot_points)) AS avg_deal_points,
       round(AVG(o.price_snapshot_points::NUMERIC / l.original_price_points), 3) AS avg_deal_ratio,
       (SELECT COUNT(*) FROM hxy.listing x WHERE x.category_id = c.category_id AND x.status = 'ON_SALE')
           AS on_sale_count
  FROM hxy.category c
  LEFT JOIN hxy.listing l ON l.category_id = c.category_id
  LEFT JOIN hxy.trade_order o ON o.listing_id = l.listing_id AND o.status = 'COMPLETED'
        AND o.completed_at >= clock_timestamp() - INTERVAL '180 days'
 GROUP BY c.category_id, c.name;

-- 管理员仪表盘统计。
CREATE OR REPLACE VIEW hxy.v_platform_stats AS
SELECT (SELECT COUNT(*) FROM hxy.app_user WHERE role = 'USER') AS user_count,
       (SELECT COUNT(*) FROM hxy.listing WHERE status = 'ON_SALE') AS on_sale_count,
       (SELECT COUNT(*) FROM hxy.trade_order WHERE status = 'COMPLETED') AS completed_orders,
       (SELECT COALESCE(SUM(price_snapshot_points), 0) FROM hxy.trade_order WHERE status = 'COMPLETED')
           AS completed_volume,
       (SELECT balance_points FROM hxy.point_account WHERE owner_type = 'PLATFORM_ESCROW') AS escrow_balance,
       (SELECT -balance_points FROM hxy.point_account WHERE owner_type = 'PLATFORM_ISSUER') AS issued_points,
       (SELECT COUNT(*) FROM hxy.order_review WHERE resolved_at IS NULL) AS open_reviews,
       -- 对账：所有账户余额之和应恒为 0；每个账户余额应等于其流水之和
       (SELECT SUM(balance_points) FROM hxy.point_account) AS balance_sum,
       (SELECT COUNT(*) FROM hxy.point_account a
         WHERE a.balance_points <> COALESCE((SELECT SUM(delta_points) FROM hxy.balance_ledger b
                                              WHERE b.account_id = a.account_id), 0)) AS mismatched_accounts;
