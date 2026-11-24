-- 航小鱼交易模块：独立演示数据与第一轮核对
-- 先运行 交易模块_独立建表草案.sql，再单独运行本文件。
-- 本文件只适合新建的 trade_demo schema 首次运行；重复运行会因主键/唯一约束报错。
-- 初始演示积分是测试数据，不属于订单付款流水；正式系统需另定初始发放规则。

BEGIN;

INSERT INTO trade_demo.user_stub (user_id, display_name)
VALUES (1001, '买家甲'), (1002, '卖家乙');

INSERT INTO trade_demo.listing_stub
    (listing_id, seller_id, current_price_points, status)
VALUES (5001, 1002, 100, 'ON_SALE');

INSERT INTO trade_demo.point_account
    (owner_type, user_id, balance_points)
VALUES
    ('USER', 1001, 500),
    ('USER', 1002, 0);

INSERT INTO trade_demo.price_history
    (listing_id, price_points, change_type, changed_at)
VALUES (5001, 100, 'INITIAL', clock_timestamp());

COMMIT;

-- 核对 1：应看到买家 500、卖家 0、平台托管 0。
SELECT account_id, owner_type, user_id, balance_points
FROM trade_demo.point_account
ORDER BY account_id;

-- 核对 2：商品 5001 当前价格应为 100，状态为 ON_SALE，卖家为 1002。
SELECT listing_id, seller_id, current_price_points, status
FROM trade_demo.listing_stub
WHERE listing_id = 5001;

-- 核对 3：商品 5001 应恰有一条 INITIAL 历史，价格为 100。
SELECT listing_id, price_points, change_type, changed_at
FROM trade_demo.price_history
WHERE listing_id = 5001
ORDER BY history_id;

-- 核对 4：这时尚无订单、转移、流水，三个计数都应为 0。
SELECT
    (SELECT COUNT(*) FROM trade_demo.trade_order) AS order_count,
    (SELECT COUNT(*) FROM trade_demo.point_transfer) AS transfer_count,
    (SELECT COUNT(*) FROM trade_demo.balance_ledger) AS ledger_count;
