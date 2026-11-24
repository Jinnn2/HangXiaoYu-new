-- 航小鱼：用户模块存储过程（PL/pgSQL 函数）
-- 一次 SELECT 调用即一个原子事务；出错时整次调用回滚。

-- 注册：建用户（触发器 T1 自动开户）并以 GRANT 转移发放初始演示积分。
CREATE OR REPLACE FUNCTION hxy.register_user(
    p_student_no     TEXT,
    p_display_name   TEXT,
    p_password       TEXT,
    p_initial_points BIGINT DEFAULT 500,
    p_role           TEXT DEFAULT 'USER'
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_user_id     BIGINT;
    v_account_id  BIGINT;
    v_issuer_id   BIGINT;
    v_transfer_id BIGINT;
BEGIN
    IF p_password IS NULL OR length(p_password) < 6 THEN
        RAISE EXCEPTION '密码至少 6 位';
    END IF;
    IF p_initial_points IS NULL OR p_initial_points < 0 THEN
        RAISE EXCEPTION '初始积分不能为负';
    END IF;
    IF EXISTS (SELECT 1 FROM hxy.app_user WHERE student_no = p_student_no) THEN
        RAISE EXCEPTION '学号 % 已注册', p_student_no;
    END IF;

    INSERT INTO hxy.app_user (student_no, display_name, password_hash, role)
    VALUES (p_student_no, btrim(p_display_name), crypt(p_password, gen_salt('bf', 8)), p_role)
    RETURNING user_id INTO v_user_id;

    IF p_initial_points > 0 THEN
        SELECT account_id INTO v_account_id FROM hxy.point_account
         WHERE owner_type = 'USER' AND user_id = v_user_id;
        SELECT account_id INTO v_issuer_id FROM hxy.point_account
         WHERE owner_type = 'PLATFORM_ISSUER' FOR UPDATE;
        UPDATE hxy.point_account SET balance_points = balance_points - p_initial_points
         WHERE account_id = v_issuer_id;
        UPDATE hxy.point_account SET balance_points = balance_points + p_initial_points
         WHERE account_id = v_account_id;
        INSERT INTO hxy.point_transfer (order_id, event_type, occurred_at)
        VALUES (NULL, 'GRANT', clock_timestamp())
        RETURNING transfer_id INTO v_transfer_id;
        INSERT INTO hxy.balance_ledger (transfer_id, account_id, delta_points)
        VALUES (v_transfer_id, v_issuer_id, -p_initial_points),
               (v_transfer_id, v_account_id, p_initial_points);
    END IF;
    RETURN v_user_id;
END $$;

-- 登录校验：成功返回用户编号，失败返回 NULL（不区分"学号不存在"和"密码错误"）。
CREATE OR REPLACE FUNCTION hxy.authenticate(p_student_no TEXT, p_password TEXT)
RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    SELECT user_id FROM hxy.app_user
     WHERE student_no = p_student_no
       AND password_hash = crypt(p_password, password_hash)
       AND status = 'ACTIVE';
$$;

CREATE OR REPLACE FUNCTION hxy.change_password(p_user_id BIGINT, p_old TEXT, p_new TEXT)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF p_new IS NULL OR length(p_new) < 6 THEN
        RAISE EXCEPTION '新密码至少 6 位';
    END IF;
    UPDATE hxy.app_user SET password_hash = crypt(p_new, gen_salt('bf', 8))
     WHERE user_id = p_user_id AND password_hash = crypt(p_old, password_hash);
    IF NOT FOUND THEN
        RAISE EXCEPTION '原密码不正确';
    END IF;
END $$;

-- 管理员角色校验，供其他函数复用。
CREATE OR REPLACE FUNCTION hxy.assert_admin(p_user_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM hxy.app_user
                    WHERE user_id = p_user_id AND role = 'ADMIN' AND status = 'ACTIVE') THEN
        RAISE EXCEPTION '用户 % 不是有效的管理员', p_user_id;
    END IF;
END $$;

-- 管理员封禁 / 解封用户。封禁后不能登录、下单、发布；其在售商品下架。
CREATE OR REPLACE FUNCTION hxy.set_user_status(p_admin_id BIGINT, p_user_id BIGINT, p_status TEXT)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM hxy.assert_admin(p_admin_id);
    IF p_status NOT IN ('ACTIVE', 'BANNED') OR p_status IS NULL THEN
        RAISE EXCEPTION '用户状态只能是 ACTIVE 或 BANNED';
    END IF;
    IF p_admin_id = p_user_id THEN
        RAISE EXCEPTION '不能修改自己的状态';
    END IF;
    UPDATE hxy.app_user SET status = p_status WHERE user_id = p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION '用户 % 不存在', p_user_id; END IF;
    IF p_status = 'BANNED' THEN
        UPDATE hxy.listing SET status = 'OFF_SHELF'
         WHERE seller_id = p_user_id AND status IN ('ON_SALE', 'RELIST_BUFFER');
    END IF;
END $$;

-- 供其他函数检查"账号可用"。
CREATE OR REPLACE FUNCTION hxy.assert_active_user(p_user_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM hxy.app_user WHERE user_id = p_user_id AND status = 'ACTIVE') THEN
        RAISE EXCEPTION '用户 % 不存在或已被封禁', p_user_id;
    END IF;
END $$;
