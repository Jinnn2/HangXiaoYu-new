-- 独立演示库增量约束；在建表后、业务写入前安装。
-- 延迟到事务提交时检查，因此允许同一事务依次写转移事件和两条流水。
BEGIN;

-- 一个订单的结算与退款最多选择一种；唯一索引也能处理并发写入。
CREATE UNIQUE INDEX one_terminal_transfer_per_order
ON trade_demo.point_transfer(order_id)
WHERE event_type IN ('SETTLEMENT', 'REFUND');

CREATE OR REPLACE FUNCTION trade_demo.assert_transfer_complete()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
DECLARE
    v_id BIGINT;
    v_transfer RECORD;
    v_rows INTEGER;
    v_correct INTEGER;
BEGIN
    v_id := NEW.transfer_id;
    SELECT t.event_type, o.price_snapshot_points AS price,
           o.buyer_id, l.seller_id
      INTO v_transfer
      FROM trade_demo.point_transfer t
      JOIN trade_demo.trade_order o ON o.order_id = t.order_id
      JOIN trade_demo.listing_stub l ON l.listing_id = o.listing_id
     WHERE t.transfer_id = v_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '转移事件 % 不存在', v_id USING ERRCODE = '23514';
    END IF;

    SELECT COUNT(*), COUNT(*) FILTER (WHERE
        (v_transfer.event_type = 'PAYMENT' AND (
            (a.owner_type = 'USER' AND a.user_id = v_transfer.buyer_id
             AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = v_transfer.price)))
        OR (v_transfer.event_type = 'SETTLEMENT' AND (
            (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'USER' AND a.user_id = v_transfer.seller_id
                AND b.delta_points = v_transfer.price)))
        OR (v_transfer.event_type = 'REFUND' AND (
            (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'USER' AND a.user_id = v_transfer.buyer_id
                AND b.delta_points = v_transfer.price)))
    ) INTO v_rows, v_correct
    FROM trade_demo.balance_ledger b
    JOIN trade_demo.point_account a ON a.account_id = b.account_id
    WHERE b.transfer_id = v_id;
    -- UNIQUE(transfer_id, account_id) 保证账户不重复；这里同时校验方向与订单金额。
    IF v_rows <> 2 OR v_correct <> 2 THEN
        RAISE EXCEPTION '转移 % 的流水不完整或账户、方向、金额错误', v_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$body$;

CREATE CONSTRAINT TRIGGER transfer_complete_on_event
AFTER INSERT ON trade_demo.point_transfer
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trade_demo.assert_transfer_complete();

CREATE CONSTRAINT TRIGGER transfer_complete_on_ledger
AFTER INSERT ON trade_demo.balance_ledger
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trade_demo.assert_transfer_complete();

CREATE OR REPLACE FUNCTION trade_demo.reject_accounting_rewrite()
RETURNS TRIGGER LANGUAGE plpgsql AS $body$
BEGIN
    RAISE EXCEPTION '已记账的 % 记录不可修改或删除；纠错需另行设计冲正流程', TG_TABLE_NAME
        USING ERRCODE = '23514';
END
$body$;

CREATE TRIGGER transfer_append_only
BEFORE UPDATE OR DELETE ON trade_demo.point_transfer
FOR EACH ROW EXECUTE FUNCTION trade_demo.reject_accounting_rewrite();
CREATE TRIGGER ledger_append_only
BEFORE UPDATE OR DELETE ON trade_demo.balance_ledger
FOR EACH ROW EXECUTE FUNCTION trade_demo.reject_accounting_rewrite();

COMMIT;
-- 边界：不禁止超级用户绕过触发器，也未由触发器自动更新账户余额。
-- 账户余额仍须通过业务事务同步维护；订单价格、商品卖家在交易后应保持固定。
-- 本文件只适合首次安装，重复安装索引或触发器会报已存在。
