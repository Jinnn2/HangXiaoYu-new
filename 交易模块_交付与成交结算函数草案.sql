-- 航小鱼交易模块：卖家交付、买家确认 / 系统自动完成。
-- 个人独立演示库 hangxiaoyu_trade_demo，依赖 trade_demo 九张表。
-- 采用 PostgreSQL 原生 PL/pgSQL；每次 SELECT 调用函数本身就是一个原子事务。
-- 先在演示库验证，再与小组 User、Listing 正式表对齐。

CREATE OR REPLACE FUNCTION trade_demo.mark_order_delivered(
    p_order_id BIGINT,
    p_seller_id BIGINT,
    p_auto_delay INTERVAL DEFAULT INTERVAL '24 hours'
) RETURNS BIGINT
LANGUAGE plpgsql
AS $delivery$
DECLARE
    v_order RECORD;
    v_now TIMESTAMPTZ;
BEGIN
    IF p_auto_delay IS NULL OR p_auto_delay <= INTERVAL '0 seconds' THEN
        RAISE EXCEPTION '自动完成等待时间必须大于 0';
    END IF;

    -- 同时锁订单和商品，避免交付与取消核实改变同一笔交易。
    SELECT o.*, l.seller_id, l.status AS listing_status
      INTO v_order
      FROM trade_demo.trade_order AS o
      JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
     WHERE o.order_id = p_order_id
     FOR UPDATE OF o, l;

    IF NOT FOUND THEN
        RAISE EXCEPTION '订单 % 不存在', p_order_id;
    END IF;
    IF v_order.seller_id <> p_seller_id THEN
        RAISE EXCEPTION '用户 % 不是订单 % 的卖家', p_seller_id, p_order_id;
    END IF;
    IF v_order.status <> 'PENDING_DELIVERY' OR v_order.listing_status <> 'TRADING' THEN
        RAISE EXCEPTION '订单 % 或商品状态不允许交付', p_order_id;
    END IF;
    IF v_order.paid_at IS NULL THEN
        RAISE EXCEPTION '订单 % 缺少付款时间', p_order_id;
    END IF;
    IF EXISTS (
        SELECT 1 FROM trade_demo.order_review
         WHERE order_id = p_order_id AND resolved_at IS NULL
    ) THEN
        RAISE EXCEPTION '订单 % 正在核实，不能交付', p_order_id;
    END IF;

    v_now := clock_timestamp();
    IF v_now >= v_order.paid_at + INTERVAL '48 hours'
       AND NOT EXISTS (
           SELECT 1 FROM trade_demo.score_event
            WHERE order_id = p_order_id
              AND score_type = 'SELLER_REPUTATION'
              AND reason = 'VERIFIED_DELIVERY_LATE'
       ) THEN
        RAISE EXCEPTION '订单 % 已超过卖家 48 小时交付期限，应先进入核实', p_order_id;
    END IF;

    UPDATE trade_demo.trade_order
       SET status = 'PENDING_RECEIPT',
           delivered_at = v_now,
           auto_complete_at = v_now + p_auto_delay
     WHERE order_id = p_order_id;
    RETURN p_order_id;
END
$delivery$;


CREATE OR REPLACE FUNCTION trade_demo.complete_order(
    p_order_id BIGINT,
    p_method TEXT,
    p_actor_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $settlement$
DECLARE
    v_order RECORD;
    v_now TIMESTAMPTZ;
    v_escrow_account_id BIGINT;
    v_seller_account_id BIGINT;
    v_escrow_balance BIGINT;
    v_transfer_id BIGINT;
    v_seller_score INTEGER;
    v_seller_gain INTEGER;
BEGIN
    IF p_method NOT IN ('BUYER_CONFIRMED', 'AUTO') OR p_method IS NULL THEN
        RAISE EXCEPTION '完成方式只能是 BUYER_CONFIRMED 或 AUTO';
    END IF;

    SELECT o.*, l.seller_id, l.status AS listing_status
      INTO v_order
      FROM trade_demo.trade_order AS o
      JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
     WHERE o.order_id = p_order_id
     FOR UPDATE OF o, l;

    IF NOT FOUND THEN
        RAISE EXCEPTION '订单 % 不存在', p_order_id;
    END IF;
    IF v_order.status <> 'PENDING_RECEIPT' OR v_order.listing_status <> 'TRADING' THEN
        RAISE EXCEPTION '订单 % 或商品状态不允许结算', p_order_id;
    END IF;
    IF v_order.delivered_at IS NULL OR v_order.auto_complete_at IS NULL THEN
        RAISE EXCEPTION '订单 % 缺少交付或自动完成时间', p_order_id;
    END IF;
    IF EXISTS (
        SELECT 1 FROM trade_demo.order_review
         WHERE order_id = p_order_id AND resolved_at IS NULL
    ) THEN
        RAISE EXCEPTION '订单 % 正在核实，不能结算', p_order_id;
    END IF;

    v_now := clock_timestamp();
    IF p_method = 'BUYER_CONFIRMED' AND p_actor_id IS DISTINCT FROM v_order.buyer_id THEN
        RAISE EXCEPTION '只有订单 % 的买家可以确认收货', p_order_id;
    END IF;
    IF p_method = 'AUTO' AND (p_actor_id IS NOT NULL OR v_now < v_order.auto_complete_at) THEN
        RAISE EXCEPTION '订单 % 尚未到自动完成时间，或自动任务传入了操作人', p_order_id;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM trade_demo.point_transfer
         WHERE order_id = p_order_id AND event_type = 'PAYMENT'
    ) OR EXISTS (
        SELECT 1 FROM trade_demo.point_transfer
         WHERE order_id = p_order_id AND event_type IN ('SETTLEMENT', 'REFUND')
    ) THEN
        RAISE EXCEPTION '订单 % 的托管资金状态不允许结算', p_order_id;
    END IF;

    SELECT account_id INTO v_escrow_account_id
      FROM trade_demo.point_account
     WHERE owner_type = 'PLATFORM_ESCROW';
    IF NOT FOUND THEN
        RAISE EXCEPTION '平台托管账户不存在';
    END IF;
    SELECT account_id INTO v_seller_account_id
      FROM trade_demo.point_account
     WHERE owner_type = 'USER' AND user_id = v_order.seller_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '卖家 % 没有积分账户', v_order.seller_id;
    END IF;

    -- 所有账户按 account_id 顺序加锁，降低多订单并发时的死锁风险。
    PERFORM account_id FROM trade_demo.point_account
     WHERE account_id IN (v_escrow_account_id, v_seller_account_id)
     ORDER BY account_id FOR UPDATE;
    SELECT balance_points INTO v_escrow_balance
      FROM trade_demo.point_account WHERE account_id = v_escrow_account_id;
    IF v_escrow_balance < v_order.price_snapshot_points THEN
        RAISE EXCEPTION '平台托管余额不足，订单 % 不能结算', p_order_id;
    END IF;

    -- 锁卖家用户行，串行化不同订单对同一卖家信誉分的计算。
    PERFORM 1 FROM trade_demo.user_stub
     WHERE user_id = v_order.seller_id FOR UPDATE;
    SELECT LEAST(100, GREATEST(0, 80 + COALESCE(SUM(delta_score), 0)))::INTEGER
      INTO v_seller_score
      FROM trade_demo.score_event
     WHERE user_id = v_order.seller_id AND score_type = 'SELLER_REPUTATION';
    v_seller_gain := LEAST(1, 100 - v_seller_score);

    UPDATE trade_demo.point_account
       SET balance_points = balance_points - v_order.price_snapshot_points
     WHERE account_id = v_escrow_account_id
       AND balance_points >= v_order.price_snapshot_points;
    IF NOT FOUND THEN
        RAISE EXCEPTION '平台托管余额被并发操作占用，订单 % 不能结算', p_order_id;
    END IF;
    UPDATE trade_demo.point_account
       SET balance_points = balance_points + v_order.price_snapshot_points
     WHERE account_id = v_seller_account_id;

    INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
    VALUES (p_order_id, 'SETTLEMENT', v_now)
    RETURNING transfer_id INTO v_transfer_id;
    INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer_id, v_escrow_account_id, -v_order.price_snapshot_points),
           (v_transfer_id, v_seller_account_id, v_order.price_snapshot_points);

    INSERT INTO trade_demo.score_event
        (order_id, user_id, score_type, reason, delta_score, occurred_at)
    VALUES (p_order_id, v_order.buyer_id, 'BUYER_REWARD', 'COMPLETION', 1, v_now),
           (p_order_id, v_order.seller_id, 'SELLER_REPUTATION', 'COMPLETION', v_seller_gain, v_now);

    UPDATE trade_demo.trade_order
       SET status = 'COMPLETED', completed_at = v_now, completion_method = p_method
     WHERE order_id = p_order_id;
    UPDATE trade_demo.listing_stub
       SET status = 'SOLD'
     WHERE listing_id = v_order.listing_id;
    RETURN p_order_id;
END
$settlement$;

-- 演示调用（将订单编号替换为实际待交付订单；一次只执行一行）：
-- SELECT trade_demo.mark_order_delivered(订单编号, 卖家编号);
-- SELECT trade_demo.complete_order(订单编号, 'BUYER_CONFIRMED', 买家编号);
-- 自动任务到期时：SELECT trade_demo.complete_order(订单编号, 'AUTO');
-- 演示缩短等待时，交付函数第三参数可填 INTERVAL '1 minute'；正式规则为 24 hours。
