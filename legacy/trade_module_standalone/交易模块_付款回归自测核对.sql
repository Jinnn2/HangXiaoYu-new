-- 在隔离库运行付款脚本之后核对原子入账。
DO $check$
DECLARE v_order_id BIGINT;
BEGIN
    SELECT order_id INTO v_order_id FROM trade_demo.trade_order
     WHERE listing_id = 5008;
    IF (SELECT status FROM trade_demo.trade_order WHERE order_id = v_order_id)
          <> 'PENDING_DELIVERY'
       OR (SELECT paid_at FROM trade_demo.trade_order WHERE order_id = v_order_id)
          IS NULL
       OR (SELECT status FROM trade_demo.listing_stub WHERE listing_id = 5008)
          <> 'TRADING'
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1001) <> 230
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'PLATFORM_ESCROW') <> 20
       OR (SELECT balance_points FROM trade_demo.point_account
            WHERE owner_type = 'USER' AND user_id = 1002) <> 250
       OR (SELECT SUM(balance_points) FROM trade_demo.point_account) <> 500
       OR (SELECT COUNT(*) FROM trade_demo.point_transfer
            WHERE order_id = v_order_id AND event_type = 'PAYMENT') <> 1
       OR (SELECT COUNT(*) FROM trade_demo.balance_ledger AS ledger
            JOIN trade_demo.point_transfer AS t ON t.transfer_id = ledger.transfer_id
            WHERE t.order_id = v_order_id) <> 2
    THEN RAISE EXCEPTION '付款脚本回归自测失败'; END IF;
END
$check$;

SELECT o.order_id, o.status, o.paid_at,
       l.status AS listing_status,
       buyer.balance_points AS buyer_points,
       escrow.balance_points AS escrow_points
FROM trade_demo.trade_order AS o
JOIN trade_demo.listing_stub AS l ON l.listing_id = o.listing_id
JOIN trade_demo.point_account AS buyer
  ON buyer.user_id = o.buyer_id AND buyer.owner_type = 'USER'
CROSS JOIN trade_demo.point_account AS escrow
WHERE o.listing_id = 5008 AND escrow.owner_type = 'PLATFORM_ESCROW';
