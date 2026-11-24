-- 在全部业务流程自测后运行，仅供隔离测试库使用。
DO $seed$
DECLARE v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (5008, 1002, 20, 'PAYMENT_RESERVED');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (5008, 20, 'INITIAL', v_now);
    INSERT INTO trade_demo.trade_order
        (listing_id, buyer_id, price_snapshot_points, status,
         created_at, payment_deadline_at)
    VALUES (5008, 1001, 20, 'PENDING_PAYMENT',
            v_now, v_now + INTERVAL '5 minutes');
END
$seed$;
