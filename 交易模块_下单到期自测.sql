-- 接在付款回归自测后，在同一个隔离测试库运行。
-- 核对未付款取消、逾期释放、下单时清理、自动结算、卖家超时核实入口。
DO $test$
DECLARE
    v_first BIGINT;
    v_expired BIGINT;
    v_third BIGINT;
    v_due BIGINT;
    v_late BIGINT;
    v_review BIGINT;
    v_rejected BOOLEAN;
    v_status TEXT;
    v_count INTEGER;
BEGIN
    INSERT INTO trade_demo.user_stub (user_id, display_name)
    VALUES (1004, '并发买家丙');
    INSERT INTO trade_demo.point_account (owner_type, user_id, balance_points)
    VALUES ('USER', 1004, 0);
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (5011, 1002, 25, 'ON_SALE');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (5011, 25, 'INITIAL', clock_timestamp());

    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.place_order(5011, 1002);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '卖家购买自己商品未被拒绝'; END IF;

    v_first := trade_demo.place_order(5011, 1001);
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.cancel_unpaid_order(v_first, 1004);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '非买家取消待付款订单未被拒绝'; END IF;
    v_status := trade_demo.cancel_unpaid_order(v_first, 1001);
    IF v_status <> 'CANCELED'
       OR (SELECT status FROM trade_demo.listing_stub WHERE listing_id = 5011) <> 'ON_SALE'
    THEN RAISE EXCEPTION '未付款主动取消或释放商品失败'; END IF;

    v_expired := trade_demo.place_order(5011, 1004);
    UPDATE trade_demo.trade_order
       SET created_at = clock_timestamp() - INTERVAL '10 minutes',
           payment_deadline_at = clock_timestamp() - INTERVAL '5 minutes'
     WHERE order_id = v_expired;
    v_third := trade_demo.place_order(5011, 1001);
    IF (SELECT status FROM trade_demo.trade_order WHERE order_id = v_expired)
          <> 'PAYMENT_EXPIRED'
       OR (SELECT status FROM trade_demo.trade_order WHERE order_id = v_third)
          <> 'PENDING_PAYMENT'
       OR (SELECT COUNT(*) FROM trade_demo.trade_order
            WHERE listing_id = 5011 AND status IN
              ('PENDING_PAYMENT','PENDING_DELIVERY','PENDING_RECEIPT','UNDER_REVIEW')) <> 1
    THEN RAISE EXCEPTION '下单时清理过期占用失败'; END IF;

    UPDATE trade_demo.trade_order
       SET created_at = clock_timestamp() - INTERVAL '10 minutes',
           payment_deadline_at = clock_timestamp() - INTERVAL '5 minutes'
     WHERE order_id = v_third;
    v_count := trade_demo.expire_unpaid_orders();
    IF v_count <> 1
       OR (SELECT status FROM trade_demo.listing_stub WHERE listing_id = 5011)
          <> 'ON_SALE'
       OR EXISTS (
           SELECT 1 FROM trade_demo.point_transfer AS t
           JOIN trade_demo.trade_order AS o ON o.order_id = t.order_id
           WHERE o.listing_id = 5011
       )
    THEN RAISE EXCEPTION '批量到期释放失败'; END IF;
    IF trade_demo.expire_unpaid_orders() <> 0 THEN
        RAISE EXCEPTION '重复执行超时任务不应再次处理订单';
    END IF;

    v_due := trade_demo.test_seed_paid_order(5012, 15, clock_timestamp());
    PERFORM trade_demo.mark_order_delivered(v_due, 1002, INTERVAL '1 millisecond');
    PERFORM pg_sleep(0.01);
    v_count := trade_demo.complete_due_orders();
    IF v_count <> 1
       OR (SELECT status FROM trade_demo.trade_order WHERE order_id = v_due)
          <> 'COMPLETED'
    THEN RAISE EXCEPTION '到期自动结算入口失败'; END IF;

    v_late := trade_demo.test_seed_paid_order(
        5013, 10, clock_timestamp() - INTERVAL '49 hours');
    v_count := trade_demo.open_late_delivery_reviews();
    IF v_count <> 1
       OR (SELECT status FROM trade_demo.trade_order WHERE order_id = v_late)
          <> 'UNDER_REVIEW'
    THEN RAISE EXCEPTION '卖家超时核实入口失败'; END IF;
    SELECT review_id INTO v_review FROM trade_demo.order_review
     WHERE order_id = v_late AND resolved_at IS NULL;
    PERFORM trade_demo.resolve_order_review(v_review, 1003, 'CANCEL', TRUE);

    IF (SELECT balance_points FROM trade_demo.point_account
         WHERE owner_type = 'USER' AND user_id = 1001) <> 215
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1002) <> 265
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'PLATFORM_ESCROW') <> 20
       OR (SELECT SUM(balance_points) FROM trade_demo.point_account) <> 500
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer
            WHERE event_type = 'SETTLEMENT') <> 5
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer
            WHERE event_type = 'REFUND') <> 3
    THEN RAISE EXCEPTION '到期任务后的积分或流水核对失败'; END IF;
END
$test$;

SELECT listing_id, status, current_price_points
FROM trade_demo.listing_stub
WHERE listing_id IN (5011,5012,5013)
ORDER BY listing_id;

SELECT status, COUNT(*) AS order_count
FROM trade_demo.trade_order
WHERE listing_id IN (5011,5012,5013)
GROUP BY status ORDER BY status;
