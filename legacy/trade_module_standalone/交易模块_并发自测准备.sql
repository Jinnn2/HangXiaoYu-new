-- 只在隔离测试库、其他自测完成后执行。
DO $seed$
DECLARE v_order BIGINT;
BEGIN
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (5014, 1002, 12, 'ON_SALE');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (5014, 12, 'INITIAL', clock_timestamp());

    v_order := trade_demo.test_seed_paid_order(5015, 12, clock_timestamp());
    PERFORM trade_demo.mark_order_delivered(v_order, 1002);
END
$seed$;
