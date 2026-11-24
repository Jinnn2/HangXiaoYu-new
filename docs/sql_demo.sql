-- 航小鱼：系统各项功能的数据库端 SQL 演示（实现报告第四节的运行结果即由本脚本生成）
-- 用法：在装好 db/01~09 的演示库中执行
--   psql -d 演示库 -X -e -f docs/sql_demo.sql > docs/sql_demo_output.txt
-- 注意：本脚本会真实修改演示数据（新增用户、商品、订单），请勿在正式库运行。

\pset footer off
\set ON_ERROR_STOP 1

-- ======================================================== 1. 用户：注册（插入）、登录（查询）、改昵称（修改）
SELECT hxy.register_user('23370099', '演示同学', 'demo123') AS new_user_id \gset
SELECT hxy.authenticate('23370099', 'demo123') AS login_ok, hxy.authenticate('23370099', 'wrong') AS login_fail;
UPDATE hxy.app_user SET display_name = '演示同学A' WHERE user_id = :new_user_id;
SELECT user_id, student_no, display_name, spendable_points, buyer_reward_points, seller_reputation
  FROM hxy.v_user_account_summary WHERE user_id = :new_user_id;
SELECT event_type, delta_points FROM hxy.v_account_statement WHERE user_id = :new_user_id;

-- ======================================================== 2. 商品：发布（插入）、搜索（查询）、修改、改价、删除
SELECT category_id AS digital FROM hxy.category WHERE name = '数码电子' \gset
SELECT hxy.create_listing(:new_user_id, :digital, '罗技 G304 无线鼠标', '电池仓有轻微划痕', 4::SMALLINT, 249, 120) AS lid \gset
SELECT listing_id, title, category_name, condition_level, current_price_points, status, seller_name
  FROM hxy.v_listing_card
 WHERE status = 'ON_SALE' AND title ILIKE '%' || '鼠标' || '%'
 ORDER BY created_at DESC;
SELECT hxy.update_listing_info(:lid, :new_user_id, :digital, '罗技 G304 无线鼠标（送鼠标垫）',
                               '电池仓有轻微划痕', 4::SMALLINT, 249, NULL);
SELECT hxy.reprice_listing(:lid, :new_user_id, 110) AS new_history_id;
SELECT history_id, price_points, change_type, changed_at FROM hxy.price_history WHERE listing_id = :lid ORDER BY history_id;

SELECT hxy.create_listing(:new_user_id, :digital, '临时发布的测试商品', '', 3::SMALLINT, NULL, 10) AS tmp_lid \gset
INSERT INTO hxy.favorite (user_id, listing_id) VALUES (2, :tmp_lid);
SELECT hxy.delete_listing(:tmp_lid, :new_user_id);
SELECT (SELECT COUNT(*) FROM hxy.listing WHERE listing_id = :tmp_lid) AS listing_left,
       (SELECT COUNT(*) FROM hxy.price_history WHERE listing_id = :tmp_lid) AS history_left,
       (SELECT COUNT(*) FROM hxy.favorite WHERE listing_id = :tmp_lid) AS favorite_left;

-- ======================================================== 3. 收藏：插入、查询、删除
INSERT INTO hxy.favorite (user_id, listing_id) VALUES (2, :lid) ON CONFLICT DO NOTHING;
SELECT f.user_id, c.title, f.created_at FROM hxy.favorite f JOIN hxy.v_listing_card c USING (listing_id) WHERE f.user_id = 2;
DELETE FROM hxy.favorite WHERE user_id = 2 AND listing_id = :lid;

-- ======================================================== 4. 智能估价：计算、保存、查询、删除
SELECT * FROM hxy.estimate_price(:digital, 4::SMALLINT, 249);
SELECT hxy.create_valuation(:new_user_id, :digital, '罗技 G304', 4::SMALLINT, 249) AS vid \gset
SELECT valuation_id, item_name, suggested_price_points, low_price_points, high_price_points, sample_count
  FROM hxy.valuation WHERE requester_id = :new_user_id;
DELETE FROM hxy.valuation WHERE valuation_id = :vid AND requester_id = :new_user_id;
SELECT * FROM hxy.v_category_market ORDER BY category_id;

-- ======================================================== 5. 交易主流程：下单 → 付款托管 → 交付 → 确认收货
SELECT hxy.place_order(:lid, 2, 110) AS oid \gset
SELECT order_id, status, price_snapshot_points, payment_deadline_at - created_at AS pay_window
  FROM hxy.trade_order WHERE order_id = :oid;
SELECT status FROM hxy.listing WHERE listing_id = :lid;
SELECT hxy.pay_order(:oid, 2) AS payment_transfer_id;
SELECT hxy.mark_order_delivered(:oid, :new_user_id);
SELECT hxy.complete_order(:oid, 'BUYER_CONFIRMED', 2);
SELECT order_id, status, completion_method, paid_at IS NOT NULL AS paid, delivered_at IS NOT NULL AS delivered
  FROM hxy.v_order_details WHERE order_id = :oid;
SELECT t.event_type, a.owner_type, a.user_id, b.delta_points
  FROM hxy.point_transfer t JOIN hxy.balance_ledger b USING (transfer_id) JOIN hxy.point_account a USING (account_id)
 WHERE t.order_id = :oid ORDER BY b.ledger_id;
SELECT user_id, display_name, spendable_points, buyer_reward_points, seller_reputation, completed_sales
  FROM hxy.v_user_account_summary WHERE user_id IN (2, :new_user_id);

-- ======================================================== 6. 业务约束：这些操作都会被数据库拒绝
\set ON_ERROR_STOP 0
SELECT hxy.complete_order(:oid, 'BUYER_CONFIRMED', 2);                          -- 重复确认
SELECT hxy.place_order((SELECT listing_id FROM hxy.listing WHERE title = 'iPad 第九代 64G 深空灰'), 6); -- 余额不足者下单后付款
SELECT hxy.pay_order(currval(pg_get_serial_sequence('hxy.trade_order', 'order_id')), 6);
UPDATE hxy.balance_ledger SET delta_points = 0;                                  -- 篡改流水
UPDATE hxy.trade_order SET status = 'COMPLETED' WHERE order_id = (SELECT max(order_id) FROM hxy.trade_order);  -- 跳过状态
DELETE FROM hxy.listing WHERE listing_id = :lid;                                 -- 删除有订单的商品
\set ON_ERROR_STOP 1

-- ======================================================== 7. 异常核实：买家申请取消 → 管理员同意 → 原额退款
SELECT r.review_id AS rid, r.order_id AS roid FROM hxy.v_open_reviews r ORDER BY review_id LIMIT 1 \gset
SELECT review_id, reason, listing_title, buyer_name, seller_name, price_snapshot_points FROM hxy.v_open_reviews;
SELECT hxy.resolve_order_review(:rid, 1, 'CANCEL', FALSE);
SELECT o.status, o.cancel_reason, l.status AS listing_status
  FROM hxy.trade_order o JOIN hxy.listing l USING (listing_id) WHERE o.order_id = :roid;
SELECT t.event_type, b.delta_points, a.owner_type FROM hxy.point_transfer t
  JOIN hxy.balance_ledger b USING (transfer_id) JOIN hxy.point_account a USING (account_id)
 WHERE t.order_id = :roid ORDER BY b.ledger_id;

-- ======================================================== 8. 定时任务入口与全平台对账
SELECT * FROM hxy.run_scheduled_tasks();
SELECT * FROM hxy.v_platform_stats;

-- ======================================================== 9. 执行计划：索引被使用
EXPLAIN SELECT * FROM hxy.trade_order WHERE buyer_id = 2 ORDER BY order_id DESC;
EXPLAIN SELECT order_id FROM hxy.trade_order WHERE status = 'PENDING_PAYMENT' AND payment_deadline_at <= now();
