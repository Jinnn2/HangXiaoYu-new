-- 用户注册、登录、初始积分发放、封禁；复式记账约束。
DO $t$
DECLARE u BIGINT; v BIGINT; l BIGINT;
BEGIN
    u := hxy_test.new_user('10001', 500);
    PERFORM hxy_test.ok(hxy_test.balance(u) = 500, '注册发放 500 初始积分');
    PERFORM hxy_test.ok((SELECT COUNT(*) FROM hxy.v_account_statement
                          WHERE user_id = u AND event_type = 'GRANT' AND delta_points = 500) = 1,
                        '初始积分有一条 GRANT 流水');
    PERFORM hxy_test.ok(hxy_test.books_balanced(), '发放后账目平衡（余额和为 0）');
    PERFORM hxy_test.ok(hxy.authenticate('10001', 'secret123') = u, '正确密码可以登录');
    PERFORM hxy_test.ok(hxy.authenticate('10001', 'wrong-pass') IS NULL, '错误密码不能登录');
    PERFORM hxy_test.ok((SELECT password_hash NOT LIKE '%secret123%' FROM hxy.app_user WHERE user_id = u),
                        '数据库不保存明文密码');
    PERFORM hxy_test.fails($$SELECT hxy.register_user('10001', 'x', 'secret123')$$, '已注册', '学号不能重复注册');
    PERFORM hxy_test.fails($$SELECT hxy.register_user('10009', 'x', '123')$$, '至少 6 位', '密码过短被拒绝');
    PERFORM hxy_test.fails($$SELECT hxy.register_user('ab', 'x', 'secret123')$$, 'student_no_format', '学号格式校验');

    PERFORM hxy.change_password(u, 'secret123', 'newpass1');
    PERFORM hxy_test.ok(hxy.authenticate('10001', 'newpass1') = u, '修改密码后新密码可登录');
    PERFORM hxy_test.fails(format('SELECT hxy.change_password(%s, %L, %L)', u, 'bad', 'x123456'),
                           '原密码不正确', '原密码错误不能改密码');

    -- 封禁
    v := hxy_test.new_user('10002');
    l := hxy.create_listing(u, 1, '测试商品', '', 4::SMALLINT, 100, 50);
    PERFORM hxy_test.fails(format('SELECT hxy.set_user_status(%s, %s, %L)', v, u, 'BANNED'),
                           '不是有效的管理员', '普通用户不能封禁他人');
    PERFORM hxy.set_user_status(1, u, 'BANNED');
    PERFORM hxy_test.ok(hxy.authenticate('10001', 'newpass1') IS NULL, '封禁用户不能登录');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'OFF_SHELF', '封禁后其在售商品下架');
    PERFORM hxy_test.fails(format('SELECT hxy.create_listing(%s, 1, %L, %L, 3::SMALLINT, 10, 5)', u, 'x', ''),
                           '已被封禁', '封禁用户不能发布商品');
    PERFORM hxy.set_user_status(1, u, 'ACTIVE');
    PERFORM hxy_test.ok(hxy.authenticate('10001', 'newpass1') = u, '解封后可以登录');
END $t$;

-- 直接篡改账务数据会被触发器拒绝。
DO $t$
DECLARE t BIGINT; a BIGINT;
BEGIN
    PERFORM hxy_test.fails('UPDATE hxy.balance_ledger SET delta_points = 1', '不可修改或删除', '流水不可修改');
    PERFORM hxy_test.fails('DELETE FROM hxy.point_transfer', '不可修改或删除', '转移记录不可删除');
    PERFORM hxy_test.fails('UPDATE hxy.point_account SET balance_points = -1 WHERE owner_type = ''USER''',
                           'point_account_balance_check', '用户余额不能为负');
END $t$;

-- 只写一侧流水的转移在提交时被延迟约束触发器拒绝（单独事务）。
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO hxy.point_transfer (order_id, event_type, occurred_at) VALUES (NULL, 'GRANT', now());
INSERT INTO hxy.balance_ledger (transfer_id, account_id, delta_points)
SELECT max(transfer_id), (SELECT account_id FROM hxy.point_account WHERE owner_type = 'PLATFORM_ISSUER'), -10
  FROM hxy.point_transfer;
COMMIT;
\set ON_ERROR_STOP 1
SELECT hxy_test.ok((SELECT COUNT(*) FROM hxy.balance_ledger WHERE delta_points = -10) = 0,
                   '单边流水在提交时被拒绝并整体回滚');
SELECT hxy_test.ok(hxy_test.books_balanced(), '篡改尝试后账目仍平衡');
