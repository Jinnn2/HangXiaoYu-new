-- 接在交付、退款自测后，在同一个隔离测试库运行。
DO $test$
DECLARE
    v_rejected BOOLEAN;
    v_history_id BIGINT;
BEGIN
    INSERT INTO trade_demo.listing_stub
        (listing_id, seller_id, current_price_points, status)
    VALUES (5007, 1002, 70, 'ON_SALE');
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (5007, 70, 'INITIAL', clock_timestamp());

    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.reprice_listing(5007, 1001, 75);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '非卖家改价未被拒绝'; END IF;

    v_history_id := trade_demo.reprice_listing(5007, 1002, 75);
    IF (SELECT current_price_points FROM trade_demo.listing_stub
         WHERE listing_id = 5007) <> 75
       OR (SELECT COUNT(*) FROM trade_demo.price_history
            WHERE listing_id = 5007) <> 2
       OR (SELECT price_points FROM trade_demo.price_history
            WHERE listing_id = 5007 AND change_type = 'INITIAL') <> 70
       OR (SELECT price_points FROM trade_demo.price_history
            WHERE history_id = v_history_id) <> 75
    THEN RAISE EXCEPTION '当前价和价格历史不一致'; END IF;

    UPDATE trade_demo.listing_stub SET status = 'PAYMENT_RESERVED'
     WHERE listing_id = 5007;
    v_rejected := FALSE;
    BEGIN
        PERFORM trade_demo.reprice_listing(5007, 1002, 80);
    EXCEPTION WHEN OTHERS THEN v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION '支付占用期间改价未被拒绝'; END IF;
    IF (SELECT COUNT(*) FROM trade_demo.price_history
         WHERE listing_id = 5007) <> 2
    THEN RAISE EXCEPTION '失败的改价不应留下历史'; END IF;
END
$test$;

SELECT l.listing_id, l.current_price_points, l.status,
       h.change_type, h.price_points
FROM trade_demo.listing_stub AS l
JOIN trade_demo.price_history AS h ON h.listing_id = l.listing_id
WHERE l.listing_id = 5007
ORDER BY h.history_id;
