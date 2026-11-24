-- 隔离库中在业务与并发自测之后运行。故意写错，确认数据库拒绝并回滚。
DO $test$
DECLARE
    v_case INTEGER;
    v_order BIGINT;
    v_transfer BIGINT;
    v_buyer BIGINT;
    v_escrow BIGINT;
    v_seller BIGINT;
    v_rejected BOOLEAN;
BEGIN
    SELECT account_id INTO v_buyer FROM trade_demo.point_account WHERE user_id = 1001;
    SELECT account_id INTO v_seller FROM trade_demo.point_account WHERE user_id = 1002;
    SELECT account_id INTO v_escrow FROM trade_demo.point_account WHERE owner_type = 'PLATFORM_ESCROW';
    FOR v_case IN 1..4 LOOP
        v_rejected := FALSE;
        BEGIN
            INSERT INTO trade_demo.listing_stub
                (listing_id, seller_id, current_price_points, status)
            VALUES (5090, 1002, 10, 'PAYMENT_RESERVED');
            INSERT INTO trade_demo.trade_order
                (listing_id, buyer_id, price_snapshot_points, status, created_at, payment_deadline_at)
            VALUES (5090,1001,10,'PENDING_PAYMENT',clock_timestamp(),clock_timestamp()+INTERVAL '5 minutes')
            RETURNING order_id INTO v_order;
            INSERT INTO trade_demo.point_transfer(order_id,event_type,occurred_at)
            VALUES(v_order,'PAYMENT',clock_timestamp()) RETURNING transfer_id INTO v_transfer;
            IF v_case > 1 THEN
                INSERT INTO trade_demo.balance_ledger(transfer_id,account_id,delta_points)
                VALUES(v_transfer,v_buyer,-10);
            END IF;
            IF v_case = 3 THEN
                -- 两条合计为零，但收款账户错误。
                INSERT INTO trade_demo.balance_ledger(transfer_id,account_id,delta_points)
                VALUES(v_transfer,v_seller,10);
            ELSIF v_case = 4 THEN
                -- 两条账户正确，但金额不平。
                INSERT INTO trade_demo.balance_ledger(transfer_id,account_id,delta_points)
                VALUES(v_transfer,v_escrow,9);
            END IF;
            SET CONSTRAINTS ALL IMMEDIATE;
        EXCEPTION WHEN check_violation THEN
            v_rejected := TRUE;
        END;
        IF NOT v_rejected THEN RAISE EXCEPTION '错误流水场景 % 未被拦截',v_case; END IF;
        IF EXISTS(SELECT 1 FROM trade_demo.listing_stub WHERE listing_id=5090) THEN
            RAISE EXCEPTION '失败写入未回滚';
        END IF;
    END LOOP;

    v_rejected := FALSE;
    BEGIN
        SELECT order_id INTO v_order FROM trade_demo.point_transfer
         WHERE event_type='SETTLEMENT' ORDER BY order_id LIMIT 1;
        INSERT INTO trade_demo.point_transfer(order_id,event_type,occurred_at)
        VALUES(v_order,'REFUND',clock_timestamp());
    EXCEPTION WHEN unique_violation THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '同单退款与结算未被拦截'; END IF;

    v_rejected := FALSE;
    BEGIN
        UPDATE trade_demo.balance_ledger SET delta_points=delta_points+1
         WHERE ledger_id=(SELECT MIN(ledger_id) FROM trade_demo.balance_ledger);
    EXCEPTION WHEN check_violation THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '修改历史流水未被拦截'; END IF;
    v_rejected := FALSE;
    BEGIN
        DELETE FROM trade_demo.balance_ledger
         WHERE ledger_id=(SELECT MIN(ledger_id) FROM trade_demo.balance_ledger);
    EXCEPTION WHEN check_violation THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '删除历史流水未被拦截'; END IF;
END
$test$;
SELECT 'PASS: 缺零条/一条流水、错误账户、错误金额、结算退款互斥、历史流水修改/删除共7项' AS constraint_test;
