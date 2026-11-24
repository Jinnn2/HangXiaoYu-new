-- 接在 交易模块_交付结算自测.sql 后，在同一个隔离测试库运行。
-- 只使用演示用户和积分，不触及真实交易。

CREATE OR REPLACE FUNCTION trade_demo.test_seed_paid_order(
    p_listing_id BIGINT, p_price BIGINT, p_paid_at TIMESTAMPTZ
) RETURNS BIGINT
LANGUAGE plpgsql
AS $seed$
DECLARE
    v_order_id BIGINT;
    v_transfer_id BIGINT;
    v_buyer_account BIGINT;
    v_escrow_account BIGINT;
BEGIN
    SELECT account_id INTO v_buyer_account FROM trade_demo.point_account
     WHERE owner_type = 'USER' AND user_id = 1001;
    SELECT account_id INTO v_escrow_account FROM trade_demo.point_account
     WHERE owner_type = 'PLATFORM_ESCROW';
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (p_listing_id, 1002, p_price, 'TRADING');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (p_listing_id, p_price, 'INITIAL', clock_timestamp());
    INSERT INTO trade_demo.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at, paid_at)
    VALUES (p_listing_id, 1001, p_price, 'PENDING_DELIVERY',
            p_paid_at - INTERVAL '1 minute', p_paid_at + INTERVAL '4 minutes', p_paid_at)
    RETURNING order_id INTO v_order_id;
    UPDATE trade_demo.point_account SET balance_points = balance_points - p_price
     WHERE account_id = v_buyer_account;
    UPDATE trade_demo.point_account SET balance_points = balance_points + p_price
     WHERE account_id = v_escrow_account;
    INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
    VALUES (v_order_id, 'PAYMENT', p_paid_at)
    RETURNING transfer_id INTO v_transfer_id;
    INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer_id, v_buyer_account, -p_price),
           (v_transfer_id, v_escrow_account, p_price);
    RETURN v_order_id;
END
$seed$;

DO $test$
DECLARE
    v_order BIGINT;
    v_review BIGINT;
    v_rejected BOOLEAN;
BEGIN
    INSERT INTO trade_demo.user_stub (user_id, display_name)
    VALUES (1003, '演示管理员');

    -- 卖家 48 小时未交付：先核实，再原额退款并扣 10 分。
    v_order := trade_demo.test_seed_paid_order(
        5003, 80, clock_timestamp() - INTERVAL '49 hours');
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.mark_order_delivered(v_order, 1002);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '超时交付未被核实流程拦截'; END IF;
    v_review := trade_demo.open_order_review(v_order, 'SELLER_DELIVERY_LATE');
    PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CANCEL', TRUE);
    IF (SELECT status FROM trade_demo.trade_order WHERE order_id = v_order) <> 'CANCELED'
       OR (SELECT status FROM trade_demo.listing_stub WHERE listing_id = 5003) <> 'RELIST_BUFFER'
       OR (SELECT delta_score FROM trade_demo.score_event
            WHERE order_id = v_order AND reason = 'VERIFIED_DELIVERY_LATE') <> -10
    THEN RAISE EXCEPTION '卖家超时退款与处罚结果错误'; END IF;
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CANCEL', TRUE);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '重复退款未被拒绝'; END IF;

    -- 买家反馈未收到：继续履行时重新计 24 小时，托管暂不出账。
    v_order := trade_demo.test_seed_paid_order(5004, 60, clock_timestamp());
    PERFORM trade_demo.mark_order_delivered(v_order, 1002);
    v_review := trade_demo.open_order_review(v_order, 'NOT_RECEIVED', 1001);
    IF (SELECT status FROM trade_demo.trade_order WHERE order_id = v_order) <> 'UNDER_REVIEW'
    THEN RAISE EXCEPTION '未收到反馈没有暂停订单'; END IF;
    PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CONTINUE', FALSE);
    IF (SELECT status FROM trade_demo.trade_order WHERE order_id = v_order) <> 'PENDING_RECEIPT'
       OR (SELECT auto_complete_at FROM trade_demo.trade_order WHERE order_id = v_order)
          < clock_timestamp() + INTERVAL '23 hours'
    THEN RAISE EXCEPTION '核实继续后未重新计时'; END IF;
    PERFORM trade_demo.complete_order(v_order, 'BUYER_CONFIRMED', 1001);

    -- 买家在待交付时申请取消：管理员同意后退款，不扣卖家信誉。
    v_order := trade_demo.test_seed_paid_order(5005, 30, clock_timestamp());
    v_review := trade_demo.open_order_review(v_order, 'BUYER_CANCEL_REQUEST', 1001);
    PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CANCEL', FALSE);
    IF EXISTS (SELECT 1 FROM trade_demo.score_event WHERE order_id = v_order)
    THEN RAISE EXCEPTION '普通取消不应产生信誉处罚或奖励'; END IF;

    -- 卖家超时但管理员允许继续：先扣分，随后允许卖家交付并完成。
    v_order := trade_demo.test_seed_paid_order(
        5006, 40, clock_timestamp() - INTERVAL '49 hours');
    v_review := trade_demo.open_order_review(v_order, 'SELLER_DELIVERY_LATE');
    PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CONTINUE', TRUE);
    PERFORM trade_demo.mark_order_delivered(v_order, 1002);
    PERFORM trade_demo.complete_order(v_order, 'BUYER_CONFIRMED', 1001);

    IF (SELECT balance_points FROM trade_demo.point_account
         WHERE owner_type = 'USER' AND user_id = 1001) <> 250
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1002) <> 250
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'PLATFORM_ESCROW') <> 0
       OR (SELECT SUM(balance_points) FROM trade_demo.point_account) <> 500
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer WHERE event_type = 'PAYMENT') <> 6
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer WHERE event_type = 'SETTLEMENT') <> 4
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer WHERE event_type = 'REFUND') <> 2
       OR (SELECT COUNT(*) FROM trade_demo.balance_ledger) <> 24
       OR (SELECT COUNT(*) FROM trade_demo.score_event) <> 10
    THEN RAISE EXCEPTION '异常流程结束后的余额、事件或流水核对失败'; END IF;
END
$test$;

SELECT o.order_id, o.status, r.reason, r.decision, l.status AS listing_status
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
LEFT JOIN trade_demo.order_review AS r ON r.order_id = o.order_id
ORDER BY o.order_id;

SELECT owner_type, user_id, balance_points
FROM trade_demo.point_account ORDER BY account_id;

SELECT event_type, COUNT(*) AS transfers
FROM trade_demo.point_transfer GROUP BY event_type ORDER BY event_type;

SELECT user_id, score_type, reason, SUM(delta_score) AS total_delta
FROM trade_demo.score_event
GROUP BY user_id, score_type, reason
ORDER BY user_id, score_type, reason;
