-- 航小鱼交易模块：买家付款后，将订单积分转入平台托管账户。
-- 运行库：hangxiaoyu_trade_demo；依赖 交易模块_独立建表草案.sql。
-- 演示顺序：先运行 交易模块_下单待付款事务草案.sql，新建未超时订单；
-- 再把下面 v_order_id 改为新订单编号，并在 5 分钟付款期限内执行整份脚本。
-- 已超时的订单不能拿来付款。本脚本只供独立演示库使用。
-- 2026-11-13：订单 2 已实跑并核对：买家 400、托管 100、卖家 0；
-- point_transfer 有 1 条 PAYMENT，关联的 balance_ledger 为 -100、+100。
-- 每次新演示都须填写实际创建的待付款订单编号，不能沿用上次的编号。

BEGIN;

DO $payment$
DECLARE
    v_order_id BIGINT := NULL; -- 填写本次实际创建的待付款订单编号
    v_order trade_demo.trade_order%ROWTYPE;
    v_buyer_account_id BIGINT;
    v_buyer_balance BIGINT;
    v_escrow_account_id BIGINT;
    v_transfer_id BIGINT;
    v_paid_at TIMESTAMPTZ;
BEGIN
    IF v_order_id IS NULL THEN
        RAISE EXCEPTION '请先填写 v_order_id 为待付款订单的实际编号';
    END IF;

    -- 锁定订单：付款和超时处理不能同时把同一订单改成不同状态。
    SELECT * INTO v_order
    FROM trade_demo.trade_order
    WHERE order_id = v_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '订单 % 不存在', v_order_id;
    END IF;
    IF v_order.status <> 'PENDING_PAYMENT' THEN
        RAISE EXCEPTION '订单 % 当前状态为 %，不能付款', v_order_id, v_order.status;
    END IF;

    SELECT account_id
    INTO v_buyer_account_id
    FROM trade_demo.point_account
    WHERE owner_type = 'USER' AND user_id = v_order.buyer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION '买家 % 没有积分账户', v_order.buyer_id;
    END IF;
    SELECT account_id INTO v_escrow_account_id
    FROM trade_demo.point_account
    WHERE owner_type = 'PLATFORM_ESCROW';

    IF NOT FOUND THEN
        RAISE EXCEPTION '平台托管账户不存在';
    END IF;

    -- 与结算、退款一致，按账户编号顺序加锁，避免反向锁顺序。
    PERFORM account_id FROM trade_demo.point_account
    WHERE account_id IN (v_buyer_account_id, v_escrow_account_id)
    ORDER BY account_id FOR UPDATE;
    SELECT balance_points INTO v_buyer_balance
    FROM trade_demo.point_account WHERE account_id = v_buyer_account_id;
    IF v_buyer_balance < v_order.price_snapshot_points THEN
        RAISE EXCEPTION '订单 % 积分不足：余额 %，价格 %',
            v_order_id, v_buyer_balance, v_order.price_snapshot_points;
    END IF;

    -- 使用同一个时间记录付款与转账；拿到锁后再检查 5 分钟期限。
    v_paid_at := clock_timestamp();
    IF v_paid_at >= v_order.payment_deadline_at THEN
        RAISE EXCEPTION '订单 % 已超过付款截止时间', v_order_id;
    END IF;

    UPDATE trade_demo.listing_stub
    SET status = 'TRADING'
    WHERE listing_id = v_order.listing_id
      AND status = 'PAYMENT_RESERVED';

    IF NOT FOUND THEN
        RAISE EXCEPTION '商品 % 未处于待付款预留状态', v_order.listing_id;
    END IF;

    UPDATE trade_demo.point_account
    SET balance_points = balance_points - v_order.price_snapshot_points
    WHERE account_id = v_buyer_account_id
      AND balance_points >= v_order.price_snapshot_points;

    IF NOT FOUND THEN
        RAISE EXCEPTION '买家账户余额不足，订单 % 付款失败', v_order_id;
    END IF;

    UPDATE trade_demo.point_account
    SET balance_points = balance_points + v_order.price_snapshot_points
    WHERE account_id = v_escrow_account_id;

    INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
    VALUES (v_order_id, 'PAYMENT', v_paid_at)
    RETURNING transfer_id INTO v_transfer_id;

    INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
    VALUES
        (v_transfer_id, v_buyer_account_id, -v_order.price_snapshot_points),
        (v_transfer_id, v_escrow_account_id, v_order.price_snapshot_points);

    UPDATE trade_demo.trade_order
    SET status = 'PENDING_DELIVERY', paid_at = v_paid_at
    WHERE order_id = v_order_id;
END
$payment$;

COMMIT;

-- 将下方的 0 改为与 v_order_id 相同的订单编号，再执行整份脚本。
-- 核对指定订单，避免把上一笔成功订单误认成本次付款结果。
SELECT o.order_id, o.status AS order_status, o.paid_at,
       l.status AS listing_status,
       buyer.balance_points AS buyer_points,
       escrow.balance_points AS escrow_points,
       (SELECT SUM(balance_points) FROM trade_demo.point_account) AS total_points
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
JOIN trade_demo.point_account AS buyer
  ON buyer.owner_type = 'USER' AND buyer.user_id = o.buyer_id
CROSS JOIN trade_demo.point_account AS escrow
WHERE o.order_id = 0
  AND escrow.owner_type = 'PLATFORM_ESCROW';

-- 执行成功的核对目标（首次付款，商品 5001 的价格为 100）：
-- 买家 1001 余额 400，平台托管余额 100，卖家 1002 余额 0；总额仍为 500。
-- 新订单状态 PENDING_DELIVERY，paid_at 非空；商品 5001 状态 TRADING。
-- point_transfer 新增 1 条 PAYMENT；balance_ledger 对这笔转账新增 -100、+100 两条。
-- 如果执行中报错，请先在当前查询工具中运行 ROLLBACK;，再检查订单和账户；
-- 报错时本事务不应留下部分付款结果。
