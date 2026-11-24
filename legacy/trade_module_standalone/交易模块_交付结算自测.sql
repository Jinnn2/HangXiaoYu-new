-- 在新建的隔离 PostgreSQL 测试库运行；不连接日常演示库。
-- 测试买家确认、系统到期完成、错误操作人、重复结算、余额守恒。

DO $test$
DECLARE
    v_first BIGINT;
    v_second BIGINT;
    v_transfer BIGINT;
    v_now TIMESTAMPTZ;
    v_rejected BOOLEAN;
    v_buyer_account BIGINT;
    v_seller_account BIGINT;
    v_escrow_account BIGINT;
BEGIN
    SELECT account_id INTO v_escrow_account FROM trade_demo.point_account
     WHERE owner_type = 'PLATFORM_ESCROW';
    SELECT account_id INTO v_buyer_account FROM trade_demo.point_account
     WHERE owner_type = 'USER' AND user_id = 1001;
    SELECT account_id INTO v_seller_account FROM trade_demo.point_account
     WHERE owner_type = 'USER' AND user_id = 1002;

    -- 第一笔：100 积分，买家主动确认。
    v_now := clock_timestamp();
    UPDATE trade_demo.listing_stub SET status = 'TRADING' WHERE listing_id = 5001;
    INSERT INTO trade_demo.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at, paid_at)
    VALUES (5001, 1001, 100, 'PENDING_DELIVERY',
            v_now - INTERVAL '1 minute', v_now + INTERVAL '4 minutes', v_now)
    RETURNING order_id INTO v_first;
    UPDATE trade_demo.point_account SET balance_points = balance_points - 100
     WHERE account_id = v_buyer_account;
    UPDATE trade_demo.point_account SET balance_points = balance_points + 100
     WHERE account_id = v_escrow_account;
    INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
    VALUES (v_first, 'PAYMENT', v_now) RETURNING transfer_id INTO v_transfer;
    INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer, v_buyer_account, -100), (v_transfer, v_escrow_account, 100);

    PERFORM trade_demo.mark_order_delivered(v_first, 1002);
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.complete_order(v_first, 'BUYER_CONFIRMED', 9999);
    EXCEPTION WHEN OTHERS THEN
        v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '非买家确认收货未被拒绝'; END IF;
    PERFORM trade_demo.complete_order(v_first, 'BUYER_CONFIRMED', 1001);

    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.complete_order(v_first, 'BUYER_CONFIRMED', 1001);
    EXCEPTION WHEN OTHERS THEN
        v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '重复结算未被拒绝'; END IF;

    -- 第二笔：50 积分，缩短演示等待时间后由系统自动完成。
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (5002, 1002, 50, 'TRADING');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (5002, 50, 'INITIAL', clock_timestamp());
    v_now := clock_timestamp();
    INSERT INTO trade_demo.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at, paid_at)
    VALUES (5002, 1001, 50, 'PENDING_DELIVERY',
            v_now - INTERVAL '1 minute', v_now + INTERVAL '4 minutes', v_now)
    RETURNING order_id INTO v_second;
    UPDATE trade_demo.point_account SET balance_points = balance_points - 50
     WHERE account_id = v_buyer_account;
    UPDATE trade_demo.point_account SET balance_points = balance_points + 50
     WHERE account_id = v_escrow_account;
    INSERT INTO trade_demo.point_transfer (order_id, event_type, occurred_at)
    VALUES (v_second, 'PAYMENT', v_now) RETURNING transfer_id INTO v_transfer;
    INSERT INTO trade_demo.balance_ledger (transfer_id, account_id, delta_points)
    VALUES (v_transfer, v_buyer_account, -50), (v_transfer, v_escrow_account, 50);

    PERFORM trade_demo.mark_order_delivered(v_second, 1002, INTERVAL '100 milliseconds');
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.complete_order(v_second, 'AUTO');
    EXCEPTION WHEN OTHERS THEN
        v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '自动完成截止前未被拒绝'; END IF;
    PERFORM pg_sleep(0.15);
    PERFORM trade_demo.complete_order(v_second, 'AUTO');

    IF (SELECT COUNT(*) FROM trade_demo.trade_order
         WHERE status = 'COMPLETED' AND completed_at IS NOT NULL) <> 2
       OR (SELECT COUNT(*) FROM trade_demo.listing_stub WHERE status = 'SOLD') <> 2
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer WHERE event_type = 'SETTLEMENT') <> 2
       OR (SELECT COUNT(*) FROM trade_demo.balance_ledger) <> 8
       OR (SELECT COUNT(*) FROM trade_demo.score_event WHERE reason = 'COMPLETION') <> 4
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE account_id = v_buyer_account) <> 350
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE account_id = v_escrow_account) <> 0
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE account_id = v_seller_account) <> 150
       OR (SELECT SUM(balance_points) FROM trade_demo.point_account) <> 500
    THEN
        RAISE EXCEPTION '交易闭环的状态、流水、奖励或余额核对失败';
    END IF;
END
$test$;

SELECT o.order_id, o.status, o.completion_method,
       l.status AS listing_status, o.price_snapshot_points
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
ORDER BY o.order_id;

SELECT owner_type, user_id, balance_points
FROM trade_demo.point_account
ORDER BY account_id;

SELECT event_type, COUNT(*) AS transfers
FROM trade_demo.point_transfer GROUP BY event_type ORDER BY event_type;
