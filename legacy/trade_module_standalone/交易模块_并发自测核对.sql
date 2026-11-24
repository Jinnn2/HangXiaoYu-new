-- 两个独立会话同时执行后的数据库结果；隔离测试库专用。
DO $check$
DECLARE v_settlement_order BIGINT;
        v_feedback_order BIGINT;
        v_escrow_expected BIGINT;
BEGIN
    SELECT order_id INTO v_settlement_order FROM trade_demo.trade_order
     WHERE listing_id = 5015;
    SELECT order_id INTO v_feedback_order FROM trade_demo.trade_order
     WHERE listing_id = 5016;
    SELECT COALESCE(SUM(price_snapshot_points), 0) INTO v_escrow_expected
      FROM trade_demo.trade_order
     WHERE status IN ('PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW');
    IF (SELECT COUNT(*) FROM trade_demo.trade_order
         WHERE listing_id = 5014 AND status = 'PENDING_PAYMENT') <> 1
       OR (SELECT buyer_id FROM trade_demo.trade_order
            WHERE listing_id = 5014 AND status = 'PENDING_PAYMENT') <> 1001
       OR (SELECT status FROM trade_demo.listing_stub
            WHERE listing_id = 5014) <> 'PAYMENT_RESERVED'
       OR (SELECT status FROM trade_demo.trade_order
            WHERE order_id = v_settlement_order) <> 'COMPLETED'
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer
            WHERE order_id = v_settlement_order AND event_type = 'SETTLEMENT') <> 1
       OR (SELECT COUNT(*) FROM trade_demo.balance_ledger AS ledger
            JOIN trade_demo.point_transfer AS t ON t.transfer_id = ledger.transfer_id
            WHERE t.order_id = v_settlement_order AND t.event_type = 'SETTLEMENT') <> 2
       OR (SELECT status FROM trade_demo.trade_order
            WHERE order_id = v_feedback_order) <> 'UNDER_REVIEW'
       OR (SELECT COUNT(*) FROM trade_demo.order_review
            WHERE order_id = v_feedback_order AND reason = 'NOT_RECEIVED'
              AND resolved_at IS NULL) <> 1
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer
            WHERE order_id = v_feedback_order AND event_type = 'SETTLEMENT') <> 0
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1001) <> 195
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1002) <> 277
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'PLATFORM_ESCROW') <> 28
       OR v_escrow_expected <> 28
       OR (SELECT SUM(balance_points) FROM trade_demo.point_account) <> 500
    THEN RAISE EXCEPTION '两个会话竞争后的订单或积分状态不正确'; END IF;
    IF EXISTS (
        SELECT 1 FROM trade_demo.point_transfer AS t
        LEFT JOIN trade_demo.balance_ledger AS l ON l.transfer_id = t.transfer_id
        GROUP BY t.transfer_id
        HAVING COUNT(l.ledger_id) <> 2 OR COALESCE(SUM(l.delta_points), 0) <> 0
    ) THEN RAISE EXCEPTION '并发测试后存在不平账的积分转移'; END IF;
END
$check$;

SELECT o.listing_id, o.order_id, o.buyer_id, o.status,
       l.status AS listing_status
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
WHERE o.listing_id IN (5014,5015,5016)
ORDER BY o.listing_id;
