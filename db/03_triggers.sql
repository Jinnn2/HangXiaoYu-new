-- 航小鱼：触发器
-- 触发器负责"无论谁写入都必须成立"的规则；业务流程本身写在 04~07 的存储过程（函数）里。

BEGIN;

-- =====================================================================
-- T1 新用户自动开设积分账户
-- =====================================================================
CREATE FUNCTION hxy.trg_user_open_account() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO hxy.point_account (owner_type, user_id, balance_points)
    VALUES ('USER', NEW.user_id, 0);
    RETURN NULL;
END $$;

CREATE TRIGGER user_open_account
AFTER INSERT ON hxy.app_user
FOR EACH ROW EXECUTE FUNCTION hxy.trg_user_open_account();

-- =====================================================================
-- T2 商品：维护 updated_at；卖家归属不可更改
-- =====================================================================
CREATE FUNCTION hxy.trg_listing_before_update() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.seller_id <> OLD.seller_id THEN
        RAISE EXCEPTION '商品的卖家归属不可修改' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END $$;

CREATE TRIGGER listing_before_update
BEFORE UPDATE ON hxy.listing
FOR EACH ROW EXECUTE FUNCTION hxy.trg_listing_before_update();

-- =====================================================================
-- T3 价格历史：商品发布写 INITIAL，改价写 REPRICE（唯一写入路径）
-- =====================================================================
CREATE FUNCTION hxy.trg_listing_price_history() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO hxy.price_history (listing_id, price_points, change_type, changed_at)
        VALUES (NEW.listing_id, NEW.current_price_points, 'INITIAL', NEW.created_at);
    ELSE
        INSERT INTO hxy.price_history (listing_id, price_points, change_type, changed_at)
        VALUES (NEW.listing_id, NEW.current_price_points, 'REPRICE', NEW.updated_at);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER listing_initial_price
AFTER INSERT ON hxy.listing
FOR EACH ROW EXECUTE FUNCTION hxy.trg_listing_price_history();

CREATE TRIGGER listing_reprice_history
AFTER UPDATE OF current_price_points ON hxy.listing
FOR EACH ROW WHEN (NEW.current_price_points IS DISTINCT FROM OLD.current_price_points)
EXECUTE FUNCTION hxy.trg_listing_price_history();

-- 价格历史只追加：不可修改；只有在所属商品已被删除（级联）时才允许删除。
CREATE FUNCTION hxy.trg_price_history_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION '价格历史不可修改' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hxy.listing WHERE listing_id = OLD.listing_id) THEN
        RAISE EXCEPTION '价格历史不可单独删除' USING ERRCODE = '23514';
    END IF;
    RETURN OLD;
END $$;

CREATE TRIGGER price_history_guard
BEFORE UPDATE OR DELETE ON hxy.price_history
FOR EACH ROW EXECUTE FUNCTION hxy.trg_price_history_guard();

-- =====================================================================
-- T4 订单：快照字段不可改；状态只能按状态机转换；终态订单不可再修改
-- =====================================================================
CREATE FUNCTION hxy.trg_order_state_machine() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.listing_id <> OLD.listing_id OR NEW.buyer_id <> OLD.buyer_id
       OR NEW.price_snapshot_points <> OLD.price_snapshot_points
       OR NEW.created_at <> OLD.created_at
       OR NEW.payment_deadline_at <> OLD.payment_deadline_at THEN
        RAISE EXCEPTION '订单 % 的商品、买家、价格快照和时间期限不可修改', OLD.order_id
            USING ERRCODE = '23514';
    END IF;
    IF OLD.status IN ('COMPLETED', 'CANCELED', 'PAYMENT_EXPIRED') THEN
        RAISE EXCEPTION '订单 % 已结束（%），不可再修改', OLD.order_id, OLD.status
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
           (OLD.status = 'PENDING_PAYMENT'  AND NEW.status IN ('PENDING_DELIVERY', 'CANCELED', 'PAYMENT_EXPIRED'))
        OR (OLD.status = 'PENDING_DELIVERY' AND NEW.status IN ('PENDING_RECEIPT', 'UNDER_REVIEW'))
        OR (OLD.status = 'PENDING_RECEIPT'  AND NEW.status IN ('COMPLETED', 'UNDER_REVIEW'))
        OR (OLD.status = 'UNDER_REVIEW'     AND NEW.status IN ('CANCELED', 'PENDING_DELIVERY', 'PENDING_RECEIPT'))
    ) THEN
        RAISE EXCEPTION '订单 % 不允许从 % 变为 %', OLD.order_id, OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER order_state_machine
BEFORE UPDATE ON hxy.trade_order
FOR EACH ROW EXECUTE FUNCTION hxy.trg_order_state_machine();

CREATE FUNCTION hxy.trg_reject_delete() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% 记录需保留用于审计，不可删除', TG_TABLE_NAME USING ERRCODE = '23514';
END $$;

CREATE TRIGGER order_no_delete
BEFORE DELETE ON hxy.trade_order
FOR EACH ROW EXECUTE FUNCTION hxy.trg_reject_delete();

-- =====================================================================
-- T5 复式记账完整性：每次转移恰好两条流水，方向、账户、金额正确（提交时检查）
-- =====================================================================
CREATE FUNCTION hxy.trg_assert_transfer_complete() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id       BIGINT := NEW.transfer_id;
    v_transfer RECORD;
    v_rows     INTEGER;
    v_correct  INTEGER;
    v_amount   BIGINT;
BEGIN
    SELECT t.event_type, o.price_snapshot_points AS price, o.buyer_id, l.seller_id
      INTO v_transfer
      FROM hxy.point_transfer t
      LEFT JOIN hxy.trade_order o ON o.order_id = t.order_id
      LEFT JOIN hxy.listing l ON l.listing_id = o.listing_id
     WHERE t.transfer_id = v_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '流水引用的转移 % 不存在', v_id USING ERRCODE = '23514';
    END IF;

    IF v_transfer.event_type = 'GRANT' THEN
        -- 发放：发行账户 −x，某个用户账户 +x
        SELECT COUNT(*),
               COUNT(*) FILTER (WHERE (a.owner_type = 'PLATFORM_ISSUER' AND b.delta_points < 0)
                                   OR (a.owner_type = 'USER' AND b.delta_points > 0)),
               SUM(b.delta_points)
          INTO v_rows, v_correct, v_amount
          FROM hxy.balance_ledger b JOIN hxy.point_account a ON a.account_id = b.account_id
         WHERE b.transfer_id = v_id;
        IF v_rows <> 2 OR v_correct <> 2 OR v_amount <> 0 THEN
            RAISE EXCEPTION '发放转移 % 的流水不完整或方向错误', v_id USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
    END IF;

    SELECT COUNT(*), COUNT(*) FILTER (WHERE
        (v_transfer.event_type = 'PAYMENT' AND (
            (a.owner_type = 'USER' AND a.user_id = v_transfer.buyer_id AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = v_transfer.price)))
        OR (v_transfer.event_type = 'SETTLEMENT' AND (
            (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'USER' AND a.user_id = v_transfer.seller_id AND b.delta_points = v_transfer.price)))
        OR (v_transfer.event_type = 'REFUND' AND (
            (a.owner_type = 'PLATFORM_ESCROW' AND b.delta_points = -v_transfer.price)
            OR (a.owner_type = 'USER' AND a.user_id = v_transfer.buyer_id AND b.delta_points = v_transfer.price))))
      INTO v_rows, v_correct
      FROM hxy.balance_ledger b JOIN hxy.point_account a ON a.account_id = b.account_id
     WHERE b.transfer_id = v_id;
    IF v_rows <> 2 OR v_correct <> 2 THEN
        RAISE EXCEPTION '转移 % 的流水不完整，或账户、方向、金额错误', v_id USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER transfer_complete_on_event
AFTER INSERT ON hxy.point_transfer
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION hxy.trg_assert_transfer_complete();

CREATE CONSTRAINT TRIGGER transfer_complete_on_ledger
AFTER INSERT ON hxy.balance_ledger
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION hxy.trg_assert_transfer_complete();

-- 已记账的转移与流水只追加，不可修改或删除。
CREATE FUNCTION hxy.trg_reject_accounting_rewrite() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '已记账的 % 记录不可修改或删除', TG_TABLE_NAME USING ERRCODE = '23514';
END $$;

CREATE TRIGGER transfer_append_only
BEFORE UPDATE OR DELETE ON hxy.point_transfer
FOR EACH ROW EXECUTE FUNCTION hxy.trg_reject_accounting_rewrite();

CREATE TRIGGER ledger_append_only
BEFORE UPDATE OR DELETE ON hxy.balance_ledger
FOR EACH ROW EXECUTE FUNCTION hxy.trg_reject_accounting_rewrite();

CREATE TRIGGER score_event_append_only
BEFORE UPDATE OR DELETE ON hxy.score_event
FOR EACH ROW EXECUTE FUNCTION hxy.trg_reject_accounting_rewrite();

COMMIT;
