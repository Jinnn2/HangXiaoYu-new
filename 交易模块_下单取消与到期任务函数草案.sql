-- 航小鱼交易模块：下单、未付款取消、待付款超时和到期任务入口。
-- PostgreSQL 原生函数；仅在独立演示库使用，正式 User/Listing 需小组对齐。
-- 定时调度器尚未接入；到期函数由任务或管理员主动 SELECT 调用。

CREATE OR REPLACE FUNCTION trade_demo.place_order(
    p_listing_id BIGINT,
    p_buyer_id BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
AS $place$
DECLARE
    v_active trade_demo.trade_order%ROWTYPE;
    v_listing trade_demo.listing_stub%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_order_id BIGINT;
BEGIN
    IF p_listing_id IS NULL OR p_buyer_id IS NULL THEN
        RAISE EXCEPTION '商品编号和买家编号不能为空';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM trade_demo.user_stub WHERE user_id = p_buyer_id) THEN
        RAISE EXCEPTION '买家 % 不存在', p_buyer_id;
    END IF;

    -- 先锁旧订单再锁商品，和付款、超时处理保持相同顺序。
    SELECT * INTO v_active FROM trade_demo.trade_order
     WHERE listing_id = p_listing_id
       AND status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY',
                      'PENDING_RECEIPT', 'UNDER_REVIEW')
     FOR UPDATE;
    IF FOUND THEN
        IF v_active.status = 'PENDING_PAYMENT'
           AND v_active.payment_deadline_at <= clock_timestamp() THEN
            UPDATE trade_demo.trade_order SET status = 'PAYMENT_EXPIRED'
             WHERE order_id = v_active.order_id;
            UPDATE trade_demo.listing_stub SET status = 'ON_SALE'
             WHERE listing_id = p_listing_id AND status = 'PAYMENT_RESERVED';
            IF NOT FOUND THEN
                RAISE EXCEPTION '过期订单 % 的商品状态不一致', v_active.order_id;
            END IF;
        ELSE
            RAISE EXCEPTION '商品 % 已被有效订单占用', p_listing_id;
        END IF;
    END IF;

    SELECT * INTO v_listing FROM trade_demo.listing_stub
     WHERE listing_id = p_listing_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '商品 % 不存在', p_listing_id; END IF;
    IF v_listing.status <> 'ON_SALE' THEN
        RAISE EXCEPTION '商品 % 当前不是在售状态', p_listing_id;
    END IF;
    IF v_listing.seller_id = p_buyer_id THEN
        RAISE EXCEPTION '卖家不能购买自己的商品 %', p_listing_id;
    END IF;
    v_now := clock_timestamp();

    UPDATE trade_demo.listing_stub SET status = 'PAYMENT_RESERVED'
     WHERE listing_id = p_listing_id;
    INSERT INTO trade_demo.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at)
    VALUES (p_listing_id, p_buyer_id, v_listing.current_price_points,
            'PENDING_PAYMENT', v_now, v_now + INTERVAL '5 minutes')
    RETURNING order_id INTO v_order_id;
    RETURN v_order_id;
END
$place$;


CREATE OR REPLACE FUNCTION trade_demo.cancel_unpaid_order(
    p_order_id BIGINT,
    p_buyer_id BIGINT
) RETURNS TEXT
LANGUAGE plpgsql
AS $cancel_unpaid$
DECLARE
    v_order trade_demo.trade_order%ROWTYPE;
    v_now TIMESTAMPTZ;
    v_new_status TEXT;
BEGIN
    SELECT * INTO v_order FROM trade_demo.trade_order
     WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '订单 % 不存在', p_order_id; END IF;
    IF v_order.buyer_id IS DISTINCT FROM p_buyer_id
       OR v_order.status <> 'PENDING_PAYMENT' THEN
        RAISE EXCEPTION '只有该待付款订单的买家能取消';
    END IF;
    v_now := clock_timestamp();
    IF v_now >= v_order.payment_deadline_at THEN
        v_new_status := 'PAYMENT_EXPIRED';
        UPDATE trade_demo.trade_order SET status = v_new_status
         WHERE order_id = p_order_id;
    ELSE
        v_new_status := 'CANCELED';
        UPDATE trade_demo.trade_order
           SET status = v_new_status, canceled_at = v_now,
               cancel_reason = 'BUYER_CANCEL_UNPAID'
         WHERE order_id = p_order_id;
    END IF;
    UPDATE trade_demo.listing_stub SET status = 'ON_SALE'
     WHERE listing_id = v_order.listing_id AND status = 'PAYMENT_RESERVED';
    IF NOT FOUND THEN
        RAISE EXCEPTION '订单 % 的商品未处于支付占用状态', p_order_id;
    END IF;
    RETURN v_new_status;
END
$cancel_unpaid$;


CREATE OR REPLACE FUNCTION trade_demo.expire_unpaid_orders(
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
        SELECT order_id, listing_id FROM trade_demo.trade_order
         WHERE status = 'PENDING_PAYMENT'
           AND payment_deadline_at <= clock_timestamp()
         ORDER BY payment_deadline_at, order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        UPDATE trade_demo.trade_order SET status = 'PAYMENT_EXPIRED'
         WHERE order_id = v_order.order_id;
        UPDATE trade_demo.listing_stub SET status = 'ON_SALE'
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


CREATE OR REPLACE FUNCTION trade_demo.complete_due_orders(
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
        SELECT order_id FROM trade_demo.trade_order
         WHERE status = 'PENDING_RECEIPT'
           AND auto_complete_at <= clock_timestamp()
         ORDER BY auto_complete_at, order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        PERFORM trade_demo.complete_order(v_order.order_id, 'AUTO');
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END
$complete_due$;


CREATE OR REPLACE FUNCTION trade_demo.open_late_delivery_reviews(
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
        SELECT o.order_id FROM trade_demo.trade_order AS o
         WHERE o.status = 'PENDING_DELIVERY'
           AND o.paid_at + INTERVAL '48 hours' <= clock_timestamp()
           AND NOT EXISTS (
               SELECT 1 FROM trade_demo.score_event AS s
                WHERE s.order_id = o.order_id
                  AND s.score_type = 'SELLER_REPUTATION'
                  AND s.reason = 'VERIFIED_DELIVERY_LATE'
           )
         ORDER BY o.paid_at, o.order_id
         FOR UPDATE SKIP LOCKED LIMIT p_limit
    LOOP
        PERFORM trade_demo.open_order_review(v_order.order_id, 'SELLER_DELIVERY_LATE');
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END
$late_reviews$;

-- 演示调用：
-- SELECT trade_demo.place_order(5001, 1001);  -- 返回新订单编号
-- SELECT trade_demo.cancel_unpaid_order(订单编号, 1001);
-- SELECT trade_demo.expire_unpaid_orders();
-- SELECT trade_demo.complete_due_orders();
-- SELECT trade_demo.open_late_delivery_reviews();
-- 上面三个批处理入口需要真实调度器定时调用，函数本身不会自动运行。
