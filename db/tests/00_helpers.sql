-- 测试辅助函数：装在测试模板库的 hxy_test schema，不进入正式库。
CREATE SCHEMA hxy_test;

-- 断言条件成立。
CREATE FUNCTION hxy_test.ok(p_cond BOOLEAN, p_msg TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL: %', p_msg;
    END IF;
    RAISE NOTICE 'ok - %', p_msg;
END $$;

-- 断言一段 SQL 会失败，且错误信息包含指定文字；失败造成的修改会被回滚（子事务）。
CREATE FUNCTION hxy_test.fails(p_sql TEXT, p_expect TEXT, p_msg TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF position(p_expect IN SQLERRM) = 0 THEN
            RAISE EXCEPTION 'FAIL: % —— 错误信息不符：%', p_msg, SQLERRM;
        END IF;
        RAISE NOTICE 'ok - % (%)', p_msg, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL: % —— 预期失败但执行成功', p_msg;
END $$;

-- 对账：全部账户余额和为 0，且每个账户余额等于其流水之和。
CREATE FUNCTION hxy_test.books_balanced() RETURNS BOOLEAN
LANGUAGE sql AS $$
    SELECT balance_sum = 0 AND mismatched_accounts = 0 FROM hxy.v_platform_stats;
$$;

CREATE FUNCTION hxy_test.balance(p_user BIGINT) RETURNS BIGINT
LANGUAGE sql AS $$
    SELECT balance_points FROM hxy.point_account WHERE user_id = p_user;
$$;

-- 测试中模拟"时间已过去"：临时关闭订单状态机触发器后修改时间字段。
CREATE FUNCTION hxy_test.shift_order_times(p_order BIGINT, p_by INTERVAL) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    ALTER TABLE hxy.trade_order DISABLE TRIGGER order_state_machine;
    UPDATE hxy.trade_order
       SET created_at = created_at - p_by,
           payment_deadline_at = payment_deadline_at - p_by,
           paid_at = paid_at - p_by,
           delivered_at = delivered_at - p_by,
           auto_complete_at = auto_complete_at - p_by,
           canceled_at = canceled_at - p_by
     WHERE order_id = p_order;
    ALTER TABLE hxy.trade_order ENABLE TRIGGER order_state_machine;
END $$;

CREATE FUNCTION hxy_test.new_user(p_no TEXT, p_points BIGINT DEFAULT 500) RETURNS BIGINT
LANGUAGE sql AS $$
    SELECT hxy.register_user(p_no, '测试' || p_no, 'secret123', p_points);
$$;

INSERT INTO hxy.category (name) VALUES ('测试分类A'), ('测试分类B');
SELECT hxy.register_user('admin', '管理员', 'secret123', 0, 'ADMIN');
