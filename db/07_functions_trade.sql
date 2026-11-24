-- 航小鱼：交易模块存储过程（由独立模块 trade_demo 版本迁移到正式表 hxy.*）
-- 一次 SELECT 调用即一个原子事务。锁顺序：订单 → 商品 → 账户（按 account_id 升序）→ 用户。

-- =====================================================================
-- 下单、付款、未付款取消、到期任务
-- =====================================================================

CREATE OR REPLACE FUNCTION hxy.place_order(
    p_listing_id BIGINT,
    p_buyer_id BIGINT,
    p_expected_price BIGINT DEFAULT NULL  -- 买家页面上看到的价格；与当前价不同则要求重新确认
) RETURNS BIGINT
LANGUAGE plpgsql
AS $place$
DECLARE
    v_active hxy.trade_order%ROWTYPE;
    v_listing hxy.listing%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_order_id BIGINT;
BEGIN
    IF p_listing_id IS NULL OR p_buyer_id IS NULL THEN
        RAISE EXCEPTION '商品编号和买家编号不能为空';
    END IF;
    PERFORM hxy.assert_active_user(p_buyer_id);

    -- 先锁旧订单再锁商品，和付款、超时处理保持相同顺序。
    SELECT * INTO v_active FROM hxy.trade_order
     WHERE listing_id = p_listing_id
       AND status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY',
                      'PENDING_RECEIPT', 'UNDER_REVIEW')
     FOR UPDATE;
    IF FOUND THEN
        IF v_active.status = 'PENDING_PAYMENT'
           AND v_active.payment_deadline_at <= clock_timestamp() THEN
            UPDATE hxy.trade_order SET status = 'PAYMENT_EXPIRED'
             WHERE order_id = v_active.order_id;
            UPDATE hxy.listing SET status = 'ON_SALE'
             WHERE listing_id = p_listing_id AND status = 'PAYMENT_RESERVED';
            IF NOT FOUND THEN
                RAISE EXCEPTION '过期订单 % 的商品状态不一致', v_active.order_id;
            END IF;
        ELSE
            RAISE EXCEPTION '商品 % 已被有效订单占用', p_listing_id;
        END IF;
    END IF;

    SELECT * INTO v_listing FROM hxy.listing
     WHERE listing_id = p_listing_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '商品 % 不存在', p_listing_id; END IF;
    IF v_listing.status <> 'ON_SALE' THEN
        RAISE EXCEPTION '商品 % 当前不是在售状态', p_listing_id;
    END IF;
    IF v_listing.seller_id = p_buyer_id THEN
        RAISE EXCEPTION '卖家不能购买自己的商品 %', p_listing_id;
    END IF;
    IF p_expected_price IS NOT NULL AND p_expected_price <> v_listing.current_price_points THEN
        RAISE EXCEPTION '商品价格已变为 % 积分，请确认后重新下单', v_listing.current_price_points;
    END IF;
    v_now := clock_timestamp();

    UPDATE hxy.listing SET status = 'PAYMENT_RESERVED'
     WHERE listing_id = p_listing_id;
    INSERT INTO hxy.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at)
    VALUES (p_listing_id, p_buyer_id, v_listing.current_price_points,
            'PENDING_PAYMENT', v_now, v_now + INTERVAL '5 minutes')
    RETURNING order_id INTO v_order_id;
    RETURN v_order_id;
END
$place$;


CREATE OR REPLACE FUNCTION hxy.cancel_unpaid_order(
    p_order_id BIGINT,
    p_buyer_id BIGINT
) RETURNS TEXT
LANGUAGE plpgsql
AS $cancel_unpaid$
DECLARE
    v_order hxy.trade_order%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_new_status TEXT;
BEGIN
    SELECT * INTO v_order FROM hxy.trade_order
     WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '订单 % 不存在', p_order_id; END IF;
    IF v_order.buyer_id IS DISTINCT FROM p_buyer_id
       OR v_order.status <> 'PENDING_PAYMENT' THEN
        RAISE EXCEPTION '只有该待付款订单的买家能取消';
    END IF;
    v_now := clock_timestamp();
    IF v_now >= v_order.payment_deadline_at THEN
        v_new_status := 'PAYMENT_EXPIRED';
        UPDATE hxy.trade_order SET status = v_new_status
         WHERE order_id = p_order_id;
    ELSE
        v_new_status := 'CANCELED';
        UPDATE hxy.trade_order
           SET status = v_new_status, canceled_at = v_now,
               cancel_reason = 'BUYER_CANCEL_UNPAID'
         WHERE order_id = p_order_id;
    END IF;
    UPDATE hxy.listing SET status = 'ON_SALE'
     WHERE listing_id = v_order.listing_id AND status = 'PAYMENT_RESERVED';
    IF NOT FOUND THEN
        RAISE EXCEPTION '订单 % 的商品未处于支付占用状态', p_order_id;
    END IF;
    RETURN v_new_status;
END
$cancel_unpaid$;


-- 付款：订单积分从买家账户转入平台托管账户。（由原"付款进入平台托管事务草案"封装而来）
CREATE OR REPLACE FUNCTION hxy.pay_order(
    p_order_id BIGINT,
    p_buyer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
AS $pay$
DECLARE
    v_order hxy.trade_order%ROWTYPE;
    v_buyer_account_id BIGINT;
    v_escrow_account_id BIGINT;
    v_buyer_balance BIGINT;
    v_transfer_id BIGINT;
    v_paid_at TIMESTAMPTZ;
BEGIN
    -- 锁定订单：付款与超时处理不能同时把同一订单改成不同状态。
    SELECT * INTO v_order FROM hxy.trade_order WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '订单 % 不存在', p_order_id; END IF;
    IF v_order.buyer_id IS DISTINCT FROM p_buyer_id THEN
        RAISE EXCEPTION '只有订单 % 的买家可以付款', p_order_id;
    END IF;
    IF v_order.status <> 'PENDING_PAYMENT' THEN
        RAISE EXCEPTION '订单 % 当前状态为 %，不能付款', p_order_id, v_order.status;
    END IF;
    PERFORM hxy.assert_active_user(p_buyer_id);

    SELECT account_id INTO v_buyer_account_id FROM hxy.point_account
     WHERE owner_type = 'USER' AND user_id = p_buyer_id;
    SELECT account_id INTO v_escrow_account_id FROM hxy.point_account
     WHERE owner_type = 'PLATFORM_ESCROW';
    IF v_buyer_account_id IS NULL OR v_escrow_account_id IS NULL THEN
        RAISE EXCEPTION '买家或平台托管账户不存在';
    END IF;

    -- 拿到订单锁后再检查期限；超时的订单不能付款。
    v_paid_at := clock_timestamp();
    IF v_paid_at >= v_order.payment_deadline_at THEN
        RAISE EXCEPTION '订单 % 已超过付款截止时间', p_order_id;
    END IF;

    UPDATE hxy.listing SET status = 'TRADING'
     WHERE listing_id = v_order.listing_id AND status = 'PAYMENT_RESERVED';
    IF NOT FOUND THEN
        RAISE EXCEPTION '商品 % 未处于支付占用状态', v_order.listing_id;
    END IF;

    -- 与结算、退款一致，按账户编号顺序加锁，避免死锁。
    PERFORM account_id FROM hxy.point_account
     WHERE account_id IN (v_buyer_account_id, v_escrow_account_id)
     ORDER BY account_id FOR UPDATE;
    SELECT balance_points INTO v_buyer_balance FROM hxy.point_account
     WHERE account_id = v_buyer_account_id;
    IF v_buyer_balance < v_order.price_snapshot_points THEN
        RAISE EXCEPTION '积分不足：余额 %，需要 %', v_buyer_balance, v_order.price_snapshot_points;
    END IF;

    UPDATE hxy.point_account SET balance_points = balance_points - v_order.price_snapshot_points
     WHERE account_id = v_buyer_account_id;
    UPDATE hxy.point_account SET balance_points = balance_points + v_order.price_snapshot_points
     WHERE account_id = v_escrow_account_id;
    INSERT INTO hxy.point_transfer (order_id, event_type, occurred_at)
    VALUES (p_order_id, 'PAYMENT', v_paid_at)
    RETURNING transfer_id INTO v_transfer_id;
    INSERT INTO hxy.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer_id, v_buyer_account_id, -v_order.price_snapshot_points),
           (v_transfer_id, v_escrow_account_id, v_order.price_snapshot_points);

    UPDATE hxy.trade_order SET status = 'PENDING_DELIVERY', paid_at = v_paid_at
     WHERE order_id = p_order_id;
    RETURN v_transfer_id;
END
$pay$;


CREATE OR REPLACE FUNCTION hxy.expire_unpaid_orders(
    p_limit INTEGER DEFAULT 100
) RETURNS INTEGER
LANGUAGE plpgsql
AS $expire_unpaid$
DECLARE
    v_order RECORD;
    v_count INTEGER := 0;
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
        RAISE EXCEPTION '每批处理量必须在 1 到 1000 之间';
    END IF;
    FOR v_order IN
        SELECT order_id, listing_id FROM hxy.trade_order
         WHERE status = 'PENDING_PAYMENT'
           AND payment_deadline_at <= clock_timestamp()
         ORDER BY payment_deadline_at, order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        UPDATE hxy.trade_order SET status = 'PAYMENT_EXPIRED'
         WHERE order_id = v_order.order_id;
        UPDATE hxy.listing SET status = 'ON_SALE'
         WHERE listing_id = v_order.listing_id
           AND status = 'PAYMENT_RESERVED';
        IF NOT FOUND THEN
            RAISE EXCEPTION '过期订单 % 的商品状态不一致', v_order.order_id;
        END IF;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END
$expire_unpaid$;


CREATE OR REPLACE FUNCTION hxy.complete_due_orders(
    p_limit INTEGER DEFAULT 100
) RETURNS INTEGER
LANGUAGE plpgsql
AS $complete_due$
DECLARE
    v_order RECORD;
    v_count INTEGER := 0;
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
        RAISE EXCEPTION '每批处理量必须在 1 到 1000 之间';
    END IF;
    FOR v_order IN
        SELECT order_id FROM hxy.trade_order
         WHERE status = 'PENDING_RECEIPT'
           AND auto_complete_at <= clock_timestamp()
         ORDER BY auto_complete_at, order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        PERFORM hxy.complete_order(v_order.order_id, 'AUTO');
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END
$complete_due$;


CREATE OR REPLACE FUNCTION hxy.open_late_delivery_reviews(
    p_limit INTEGER DEFAULT 100
) RETURNS INTEGER
LANGUAGE plpgsql
AS $late_reviews$
DECLARE
    v_order RECORD;
    v_count INTEGER := 0;
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
        RAISE EXCEPTION '每批处理量必须在 1 到 1000 之间';
    END IF;
    FOR v_order IN
        SELECT o.order_id FROM hxy.trade_order AS o
         WHERE o.status = 'PENDING_DELIVERY'
           AND o.paid_at + INTERVAL '48 hours' <= clock_timestamp()
           AND NOT EXISTS (
               SELECT 1 FROM hxy.score_event AS s
                WHERE s.order_id = o.order_id
                  AND s.score_type = 'SELLER_REPUTATION'
                  AND s.reason = 'VERIFIED_DELIVERY_LATE'
           )
         ORDER BY o.paid_at, o.order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        PERFORM hxy.open_order_review(v_order.order_id, 'SELLER_DELIVERY_LATE');
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END
$late_reviews$;

-- =====================================================================
-- 交付、确认收货 / 自动完成结算
-- =====================================================================

CREATE OR REPLACE FUNCTION hxy.mark_order_delivered(
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
      FROM hxy.trade_order AS o
      JOIN hxy.listing AS l ON l.listing_id = o.listing_id
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
        SELECT 1 FROM hxy.order_review
         WHERE order_id = p_order_id AND resolved_at IS NULL
    ) THEN
        RAISE EXCEPTION '订单 % 正在核实，不能交付', p_order_id;
    END IF;

    v_now := clock_timestamp();
    IF v_now >= v_order.paid_at + INTERVAL '48 hours'
       AND NOT EXISTS (
           SELECT 1 FROM hxy.score_event
            WHERE order_id = p_order_id
              AND score_type = 'SELLER_REPUTATION'
              AND reason = 'VERIFIED_DELIVERY_LATE'
       ) THEN
        RAISE EXCEPTION '订单 % 已超过卖家 48 小时交付期限，应先进入核实', p_order_id;
    END IF;

    UPDATE hxy.trade_order
       SET status = 'PENDING_RECEIPT',
           delivered_at = v_now,
           auto_complete_at = v_now + p_auto_delay
     WHERE order_id = p_order_id;
    RETURN p_order_id;
END
$delivery$;


CREATE OR REPLACE FUNCTION hxy.complete_order(
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
      FROM hxy.trade_order AS o
      JOIN hxy.listing AS l ON l.listing_id = o.listing_id
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
        SELECT 1 FROM hxy.order_review
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
        SELECT 1 FROM hxy.point_transfer
         WHERE order_id = p_order_id AND event_type = 'PAYMENT'
    ) OR EXISTS (
        SELECT 1 FROM hxy.point_transfer
         WHERE order_id = p_order_id AND event_type IN ('SETTLEMENT', 'REFUND')
    ) THEN
        RAISE EXCEPTION '订单 % 的托管资金状态不允许结算', p_order_id;
    END IF;

    SELECT account_id INTO v_escrow_account_id
      FROM hxy.point_account
     WHERE owner_type = 'PLATFORM_ESCROW';
    IF NOT FOUND THEN
        RAISE EXCEPTION '平台托管账户不存在';
    END IF;
    SELECT account_id INTO v_seller_account_id
      FROM hxy.point_account
     WHERE owner_type = 'USER' AND user_id = v_order.seller_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '卖家 % 没有积分账户', v_order.seller_id;
    END IF;

    -- 所有账户按 account_id 顺序加锁，降低多订单并发时的死锁风险。
    PERFORM account_id FROM hxy.point_account
     WHERE account_id IN (v_escrow_account_id, v_seller_account_id)
     ORDER BY account_id FOR UPDATE;
    SELECT balance_points INTO v_escrow_balance
      FROM hxy.point_account WHERE account_id = v_escrow_account_id;
    IF v_escrow_balance < v_order.price_snapshot_points THEN
        RAISE EXCEPTION '平台托管余额不足，订单 % 不能结算', p_order_id;
    END IF;

    -- 锁卖家用户行，串行化不同订单对同一卖家信誉分的计算。
    PERFORM 1 FROM hxy.app_user
     WHERE user_id = v_order.seller_id FOR UPDATE;
    SELECT LEAST(100, GREATEST(0, 80 + COALESCE(SUM(delta_score), 0)))::INTEGER
      INTO v_seller_score
      FROM hxy.score_event
     WHERE user_id = v_order.seller_id AND score_type = 'SELLER_REPUTATION';
    v_seller_gain := LEAST(1, 100 - v_seller_score);

    UPDATE hxy.point_account
       SET balance_points = balance_points - v_order.price_snapshot_points
     WHERE account_id = v_escrow_account_id
       AND balance_points >= v_order.price_snapshot_points;
    IF NOT FOUND THEN
        RAISE EXCEPTION '平台托管余额被并发操作占用，订单 % 不能结算', p_order_id;
    END IF;
    UPDATE hxy.point_account
       SET balance_points = balance_points + v_order.price_snapshot_points
     WHERE account_id = v_seller_account_id;

    INSERT INTO hxy.point_transfer (order_id, event_type, occurred_at)
    VALUES (p_order_id, 'SETTLEMENT', v_now)
    RETURNING transfer_id INTO v_transfer_id;
    INSERT INTO hxy.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer_id, v_escrow_account_id, -v_order.price_snapshot_points),
           (v_transfer_id, v_seller_account_id, v_order.price_snapshot_points);

    INSERT INTO hxy.score_event
        (order_id, user_id, score_type, reason, delta_score, occurred_at)
    VALUES (p_order_id, v_order.buyer_id, 'BUYER_REWARD', 'COMPLETION', 1, v_now),
           (p_order_id, v_order.seller_id, 'SELLER_REPUTATION', 'COMPLETION', v_seller_gain, v_now);

    UPDATE hxy.trade_order
       SET status = 'COMPLETED', completed_at = v_now, completion_method = p_method
     WHERE order_id = p_order_id;
    UPDATE hxy.listing
       SET status = 'SOLD'
     WHERE listing_id = v_order.listing_id;
    RETURN p_order_id;
END
$settlement$;

-- =====================================================================
-- 异常核实与退款（重新上架缓冲期从 trade_order.canceled_at 起算，见 release_relist_buffers）
-- =====================================================================

CREATE OR REPLACE FUNCTION hxy.open_order_review(
    p_order_id BIGINT,
    p_reason TEXT,
    p_actor_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $open_review$
DECLARE
    v_order hxy.trade_order%ROWTYPE;
    v_review_id BIGINT;
    v_now TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_order FROM hxy.trade_order
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

    INSERT INTO hxy.order_review (order_id, reason, previous_status, opened_at)
    VALUES (p_order_id, p_reason, v_order.status, v_now)
    RETURNING review_id INTO v_review_id;
    UPDATE hxy.trade_order SET status = 'UNDER_REVIEW'
     WHERE order_id = p_order_id;
    RETURN v_review_id;
END
$open_review$;


CREATE OR REPLACE FUNCTION hxy.resolve_order_review(
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
    v_review hxy.order_review%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_escrow_account_id BIGINT;
    v_buyer_account_id BIGINT;
    v_escrow_balance BIGINT;
    v_transfer_id BIGINT;
    v_seller_score INTEGER;
    v_seller_penalty INTEGER;
BEGIN
    PERFORM hxy.assert_admin(p_admin_id);
    IF p_decision NOT IN ('CANCEL', 'CONTINUE') OR p_decision IS NULL THEN
        RAISE EXCEPTION '核实结论只能是 CANCEL 或 CONTINUE';
    END IF;
    IF p_verified_delivery_late IS NULL THEN
        RAISE EXCEPTION '是否核实卖家超时必须明确';
    END IF;

    -- 全部入口先锁订单，再锁核实记录；同一订单的结算和退款不能并行成功。
    SELECT order_id INTO v_order_id FROM hxy.order_review
     WHERE review_id = p_review_id;
    IF NOT FOUND THEN RAISE EXCEPTION '核实记录 % 不存在', p_review_id; END IF;
    SELECT o.*, l.seller_id, l.status AS listing_status
      INTO v_order
      FROM hxy.trade_order AS o
      JOIN hxy.listing AS l ON l.listing_id = o.listing_id
     WHERE o.order_id = v_order_id
     FOR UPDATE OF o, l;
    SELECT * INTO v_review FROM hxy.order_review
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
            SELECT 1 FROM hxy.score_event
             WHERE order_id = v_order_id AND score_type = 'SELLER_REPUTATION'
               AND reason = 'VERIFIED_DELIVERY_LATE'
        ) THEN
            RAISE EXCEPTION '订单 % 的卖家超时处罚已记录', v_order_id;
        END IF;
    END IF;

    IF p_decision = 'CANCEL' THEN
        IF NOT EXISTS (
            SELECT 1 FROM hxy.point_transfer
             WHERE order_id = v_order_id AND event_type = 'PAYMENT'
        ) OR EXISTS (
            SELECT 1 FROM hxy.point_transfer
             WHERE order_id = v_order_id AND event_type IN ('SETTLEMENT', 'REFUND')
        ) THEN RAISE EXCEPTION '订单 % 的托管状态不允许退款', v_order_id; END IF;

        SELECT account_id INTO v_escrow_account_id FROM hxy.point_account
         WHERE owner_type = 'PLATFORM_ESCROW';
        IF NOT FOUND THEN RAISE EXCEPTION '平台托管账户不存在'; END IF;
        SELECT account_id INTO v_buyer_account_id FROM hxy.point_account
         WHERE owner_type = 'USER' AND user_id = v_order.buyer_id;
        IF NOT FOUND THEN RAISE EXCEPTION '买家 % 没有积分账户', v_order.buyer_id; END IF;
        PERFORM account_id FROM hxy.point_account
         WHERE account_id IN (v_escrow_account_id, v_buyer_account_id)
         ORDER BY account_id FOR UPDATE;
        SELECT balance_points INTO v_escrow_balance FROM hxy.point_account
         WHERE account_id = v_escrow_account_id;
        IF v_escrow_balance < v_order.price_snapshot_points THEN
            RAISE EXCEPTION '平台托管余额不足，订单 % 不能退款', v_order_id;
        END IF;
    END IF;

    IF p_verified_delivery_late THEN
        PERFORM 1 FROM hxy.app_user
         WHERE user_id = v_order.seller_id FOR UPDATE;
        SELECT LEAST(100, GREATEST(0, 80 + COALESCE(SUM(delta_score), 0)))::INTEGER
          INTO v_seller_score FROM hxy.score_event
         WHERE user_id = v_order.seller_id AND score_type = 'SELLER_REPUTATION';
        v_seller_penalty := -LEAST(10, v_seller_score);
        INSERT INTO hxy.score_event
            (order_id, user_id, score_type, reason, delta_score, occurred_at, operator_id)
        VALUES (v_order_id, v_order.seller_id, 'SELLER_REPUTATION',
                'VERIFIED_DELIVERY_LATE', v_seller_penalty, v_now, p_admin_id);
    END IF;

    IF p_decision = 'CANCEL' THEN
        UPDATE hxy.point_account
           SET balance_points = balance_points - v_order.price_snapshot_points
         WHERE account_id = v_escrow_account_id
           AND balance_points >= v_order.price_snapshot_points;
        IF NOT FOUND THEN RAISE EXCEPTION '托管积分被并发操作占用'; END IF;
        UPDATE hxy.point_account
           SET balance_points = balance_points + v_order.price_snapshot_points
         WHERE account_id = v_buyer_account_id;
        INSERT INTO hxy.point_transfer (order_id, event_type, occurred_at)
        VALUES (v_order_id, 'REFUND', v_now)
        RETURNING transfer_id INTO v_transfer_id;
        INSERT INTO hxy.balance_ledger (transfer_id, account_id, delta_points)
        VALUES (v_transfer_id, v_escrow_account_id, -v_order.price_snapshot_points),
               (v_transfer_id, v_buyer_account_id, v_order.price_snapshot_points);
        UPDATE hxy.trade_order
           SET status = 'CANCELED', canceled_at = v_now,
               cancel_reason = v_review.reason
         WHERE order_id = v_order_id;
        UPDATE hxy.listing SET status = 'RELIST_BUFFER'
         WHERE listing_id = v_order.listing_id;
    ELSE
        IF v_review.previous_status = 'PENDING_RECEIPT' THEN
            UPDATE hxy.trade_order
               SET status = 'PENDING_RECEIPT',
                   auto_complete_at = v_now + INTERVAL '24 hours'
             WHERE order_id = v_order_id;
        ELSE
            UPDATE hxy.trade_order SET status = 'PENDING_DELIVERY'
             WHERE order_id = v_order_id;
        END IF;
    END IF;

    UPDATE hxy.order_review
       SET decision = p_decision, resolved_at = v_now, admin_id = p_admin_id
     WHERE review_id = p_review_id;
    RETURN v_order_id;
END
$resolve_review$;



-- =====================================================================
-- 定时任务总入口：后端调度器每隔一段时间调用一次
-- =====================================================================
CREATE OR REPLACE FUNCTION hxy.run_scheduled_tasks(
    OUT expired_orders INTEGER,
    OUT auto_completed INTEGER,
    OUT late_reviews INTEGER,
    OUT relisted INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    expired_orders := hxy.expire_unpaid_orders();
    auto_completed := hxy.complete_due_orders();
    late_reviews   := hxy.open_late_delivery_reviews();
    relisted       := hxy.release_relist_buffers();
END $$;
