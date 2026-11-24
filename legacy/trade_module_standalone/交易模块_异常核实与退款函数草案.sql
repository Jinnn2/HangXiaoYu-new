-- 航小鱼交易模块：买家申请、交付超时、未收到商品的核实与退款。
-- 独立演示库的原生 SQL 草案；管理员角色校验依赖小组正式 User 表，当前只校验管理员编号存在。
-- 24 小时重新上架缓冲使用 trade_order.canceled_at 推算；自动上架仍待商品组字段和任务调度对齐。

CREATE OR REPLACE FUNCTION trade_demo.open_order_review(
    p_order_id BIGINT,
    p_reason TEXT,
    p_actor_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $open_review$
DECLARE
    v_order trade_demo.trade_order%ROWTYPE;
    v_review_id BIGINT;
    v_now TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_order FROM trade_demo.trade_order
     WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '订单 % 不存在', p_order_id; END IF;
    v_now := clock_timestamp();

    IF p_reason = 'BUYER_CANCEL_REQUEST' THEN
        IF v_order.status <> 'PENDING_DELIVERY'
           OR p_actor_id IS DISTINCT FROM v_order.buyer_id THEN
            RAISE EXCEPTION '仅待交付订单的买家可申请取消';
        END IF;
    ELSIF p_reason = 'NOT_RECEIVED' THEN
        IF v_order.status <> 'PENDING_RECEIPT'
           OR p_actor_id IS DISTINCT FROM v_order.buyer_id
           OR v_order.auto_complete_at IS NULL
           OR v_now >= v_order.auto_complete_at THEN
            RAISE EXCEPTION '仅自动完成期限前、待收货订单的买家可反馈未收到';
        END IF;
    ELSIF p_reason = 'SELLER_DELIVERY_LATE' THEN
        IF v_order.status <> 'PENDING_DELIVERY'
           OR p_actor_id IS NOT NULL
           OR v_order.paid_at IS NULL
           OR v_now < v_order.paid_at + INTERVAL '48 hours' THEN
            RAISE EXCEPTION '订单 % 尚不符合系统发起交付超时核实的条件', p_order_id;
        END IF;
    ELSE
        RAISE EXCEPTION '未知核实原因 %', p_reason;
    END IF;

    INSERT INTO trade_demo.order_review (order_id, reason, previous_status, opened_at)
    VALUES (p_order_id, p_reason, v_order.status, v_now)
    RETURNING review_id INTO v_review_id;
    UPDATE trade_demo.trade_order SET status = 'UNDER_REVIEW'
     WHERE order_id = p_order_id;
    RETURN v_review_id;
END
$open_review$;


CREATE OR REPLACE FUNCTION trade_demo.resolve_order_review(
    p_review_id BIGINT,
    p_admin_id BIGINT,
    p_decision TEXT,
    p_verified_delivery_late BOOLEAN DEFAULT FALSE
) RETURNS BIGINT
LANGUAGE plpgsql
AS $resolve_review$
DECLARE
    v_order_id BIGINT;
    v_order RECORD;
    v_review trade_demo.order_review%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_escrow_account_id BIGINT;
    v_buyer_account_id BIGINT;
    v_escrow_balance BIGINT;
    v_transfer_id BIGINT;
    v_seller_score INTEGER;
    v_seller_penalty INTEGER;
BEGIN
    IF p_admin_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM trade_demo.user_stub WHERE user_id = p_admin_id
    ) THEN RAISE EXCEPTION '管理员编号 % 不存在', p_admin_id; END IF;
    IF p_decision NOT IN ('CANCEL', 'CONTINUE') OR p_decision IS NULL THEN
        RAISE EXCEPTION '核实结论只能是 CANCEL 或 CONTINUE';
    END IF;
    IF p_verified_delivery_late IS NULL THEN
        RAISE EXCEPTION '是否核实卖家超时必须明确';
    END IF;

    -- 全部入口先锁订单，再锁核实记录；同一订单的结算和退款不能并行成功。
    SELECT order_id INTO v_order_id FROM trade_demo.order_review
     WHERE review_id = p_review_id;
    IF NOT FOUND THEN RAISE EXCEPTION '核实记录 % 不存在', p_review_id; END IF;
    SELECT o.*, l.seller_id, l.status AS listing_status
      INTO v_order
      FROM trade_demo.trade_order AS o
      JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
     WHERE o.order_id = v_order_id
     FOR UPDATE OF o, l;
    SELECT * INTO v_review FROM trade_demo.order_review
     WHERE review_id = p_review_id FOR UPDATE;
    IF v_review.resolved_at IS NOT NULL OR v_order.status <> 'UNDER_REVIEW'
       OR v_order.listing_status <> 'TRADING' THEN
        RAISE EXCEPTION '核实记录 % 已处理，或订单/商品状态不允许处理', p_review_id;
    END IF;
    IF v_review.previous_status NOT IN ('PENDING_DELIVERY', 'PENDING_RECEIPT') THEN
        RAISE EXCEPTION '核实记录 % 的原状态无效', p_review_id;
    END IF;
    v_now := clock_timestamp();

    IF p_verified_delivery_late THEN
        IF v_order.paid_at IS NULL
           OR v_now < v_order.paid_at + INTERVAL '48 hours'
           OR (v_order.delivered_at IS NOT NULL
               AND v_order.delivered_at < v_order.paid_at + INTERVAL '48 hours') THEN
            RAISE EXCEPTION '订单 % 不符合已核实超时未交付的时间证据', v_order_id;
        END IF;
        IF EXISTS (
            SELECT 1 FROM trade_demo.score_event
             WHERE order_id = v_order_id AND score_type = 'SELLER_REPUTATION'
               AND reason = 'VERIFIED_DELIVERY_LATE'
        ) THEN
            RAISE EXCEPTION '订单 % 的卖家超时处罚已记录', v_order_id;
        END IF;
    END IF;

    IF p_decision = 'CANCEL' THEN
        IF NOT EXISTS (
            SELECT 1 FROM trade_demo.point_transfer
             WHERE order_id = v_order_id AND event_type = 'PAYMENT'
        ) OR EXISTS (
            SELECT 1 FROM trade_demo.point_transfer
             WHERE order_id = v_order_id AND event_type IN ('SETTLEMENT', 'REFUND')
        ) THEN RAISE EXCEPTION '订单 % 的托管状态不允许退款', v_order_id; END IF;

        SELECT account_id INTO v_escrow_account_id FROM trade_demo.point_account
         WHERE owner_type = 'PLATFORM_ESCROW';
        IF NOT FOUND THEN RAISE EXCEPTION '平台托管账户不存在'; END IF;
        SELECT account_id INTO v_buyer_account_id FROM trade_demo.point_account
         WHERE owner_type = 'USER' AND user_id = v_order.buyer_id;
        IF NOT FOUND THEN RAISE EXCEPTION '买家 % 没有积分账户', v_order.buyer_id; END IF;
        PERFORM account_id FROM trade_demo.point_account
         WHERE account_id IN (v_escrow_account_id, v_buyer_account_id)
         ORDER BY account_id FOR UPDATE;
        SELECT balance_points INTO v_escrow_balance FROM trade_demo.point_account
         WHERE account_id = v_escrow_account_id;
        IF v_escrow_balance < v_order.price_snapshot_points THEN
            RAISE EXCEPTION '平台托管余额不足，订单 % 不能退款', v_order_id;
        END IF;
    END IF;

    IF p_verified_delivery_late THEN
        PERFORM 1 FROM trade_demo.user_stub
         WHERE user_id = v_order.seller_id FOR UPDATE;
        SELECT LEAST(100, GREATEST(0, 80 + COALESCE(SUM(delta_score), 0)))::INTEGER
          INTO v_seller_score FROM trade_demo.score_event
         WHERE user_id = v_order.seller_id AND score_type = 'SELLER_REPUTATION';
        v_seller_penalty := -LEAST(10, v_seller_score);
        INSERT INTO trade_demo.score_event
            (order_id, user_id, score_type, reason, delta_score, occurred_at, operator_id)
        VALUES (v_order_id, v_order.seller_id, 'SELLER_REPUTATION',
                'VERIFIED_DELIVERY_LATE', v_seller_penalty, v_now, p_admin_id);
    END IF;

    IF p_decision = 'CANCEL' THEN
        UPDATE trade_demo.point_account
           SET balance_points = balance_points - v_order.price_snapshot_points
         WHERE account_id = v_escrow_account_id
           AND balance_points >= v_order.price_snapshot_points;
        IF NOT FOUND THEN RAISE EXCEPTION '托管积分被并发操作占用'; END IF;
        UPDATE trade_demo.point_account
           SET balance_points = balance_points + v_order.price_snapshot_points
         WHERE account_id = v_buyer_account_id;
        INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
        VALUES (v_order_id, 'REFUND', v_now)
        RETURNING transfer_id INTO v_transfer_id;
        INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
        VALUES (v_transfer_id, v_escrow_account_id, -v_order.price_snapshot_points),
               (v_transfer_id, v_buyer_account_id, v_order.price_snapshot_points);
        UPDATE trade_demo.trade_order
           SET status = 'CANCELED', canceled_at = v_now,
               cancel_reason = v_review.reason
         WHERE order_id = v_order_id;
        UPDATE trade_demo.listing_stub SET status = 'RELIST_BUFFER'
         WHERE listing_id = v_order.listing_id;
    ELSE
        IF v_review.previous_status = 'PENDING_RECEIPT' THEN
            UPDATE trade_demo.trade_order
               SET status = 'PENDING_RECEIPT',
                   auto_complete_at = v_now + INTERVAL '24 hours'
             WHERE order_id = v_order_id;
        ELSE
            UPDATE trade_demo.trade_order SET status = 'PENDING_DELIVERY'
             WHERE order_id = v_order_id;
        END IF;
    END IF;

    UPDATE trade_demo.order_review
       SET decision = p_decision, resolved_at = v_now, admin_id = p_admin_id
     WHERE review_id = p_review_id;
    RETURN v_order_id;
END
$resolve_review$;

-- 示例（把编号换成真实订单、核实记录和管理员编号）：
-- 买家申请取消：SELECT trade_demo.open_order_review(订单编号, 'BUYER_CANCEL_REQUEST', 买家编号);
-- 买家反馈未收到：SELECT trade_demo.open_order_review(订单编号, 'NOT_RECEIVED', 买家编号);
-- 系统发现卖家超时：SELECT trade_demo.open_order_review(订单编号, 'SELLER_DELIVERY_LATE');
-- 管理员确认违约并取消：SELECT trade_demo.resolve_order_review(核实编号, 管理员编号, 'CANCEL', TRUE);
-- 管理员允许继续履行：SELECT trade_demo.resolve_order_review(核实编号, 管理员编号, 'CONTINUE', FALSE);
