-- 航小鱼：演示数据。只在新建的演示库执行一次。
-- 全部通过存储过程写入，因此账户、流水、价格历史、评分都与真实操作一致。
-- 演示账号密码均为 123456；管理员学号 admin。

BEGIN;

INSERT INTO hxy.category (name, sort_order) VALUES
    ('数码电子', 1), ('教材书籍', 2), ('生活用品', 3), ('运动户外', 4),
    ('服饰鞋包', 5), ('乐器文娱', 6), ('其他', 99);

DO $seed$
DECLARE
    v_admin BIGINT; a BIGINT; b BIGINT; c BIGINT; d BIGINT; e BIGINT;
    cat_digital INT; cat_book INT; cat_life INT; cat_sport INT; cat_cloth INT; cat_fun INT;
    l BIGINT; o BIGINT; i INT;
    r RECORD;
    history BIGINT[] := '{}';
BEGIN
    v_admin := hxy.register_user('admin',    '平台管理员', '123456', 0, 'ADMIN');
    a := hxy.register_user('23370001', '林同学', '123456', 800);
    b := hxy.register_user('23370002', '王同学', '123456', 800);
    c := hxy.register_user('23370003', '陈同学', '123456', 800);
    d := hxy.register_user('23370004', '赵同学', '123456', 800);
    e := hxy.register_user('23370005', '周同学', '123456', 500);

    SELECT category_id INTO cat_digital FROM hxy.category WHERE name = '数码电子';
    SELECT category_id INTO cat_book    FROM hxy.category WHERE name = '教材书籍';
    SELECT category_id INTO cat_life    FROM hxy.category WHERE name = '生活用品';
    SELECT category_id INTO cat_sport   FROM hxy.category WHERE name = '运动户外';
    SELECT category_id INTO cat_cloth   FROM hxy.category WHERE name = '服饰鞋包';
    SELECT category_id INTO cat_fun     FROM hxy.category WHERE name = '乐器文娱';

    -- ---------- 已完成的历史成交（为智能估价与看板提供样本；ago = 几天前完成）
    FOR r IN SELECT * FROM (VALUES
        (b, a, cat_digital, '罗技 M330 静音鼠标',        4::SMALLINT, 99,  60,  1),
        (c, d, cat_digital, '小米蓝牙耳机 Air2',          3::SMALLINT, 199, 95,  3),
        (d, a, cat_digital, '64GB U 盘',                 5::SMALLINT, 59,  45,  5),
        (b, c, cat_book,    '高等数学（同济第八版）上册',    3::SMALLINT, 52,  18,  7),
        (a, c, cat_book,    '数据库系统概论 第六版',      4::SMALLINT, 59,  30,  8),
        (d, b, cat_book,    '线性代数辅导讲义',           2::SMALLINT, 45,  12,  10),
        (c, b, cat_life,    '宿舍小台灯',                 4::SMALLINT, 89,  50,  11),
        (a, d, cat_life,    '折叠收纳箱 两只装',           3::SMALLINT, 60,  25,  13),
        (b, d, cat_sport,   '尤尼克斯羽毛球拍',            3::SMALLINT, 299, 140, 16),
        (c, a, cat_sport,   '瑜伽垫 加厚',                4::SMALLINT, 79,  40,  20),
        (c, b, cat_digital, '小米充电宝 10000mAh',        4::SMALLINT, 129, 65,  2),
        (a, d, cat_book,    '大学物理 第三版',            3::SMALLINT, 48,  15,  4),
        (d, c, cat_life,    '宿舍收纳推车',               4::SMALLINT, 79,  38,  6),
        (b, a, cat_sport,   '护膝一对',                   5::SMALLINT, 69,  50,  9),
        (c, d, cat_cloth,   '优衣库羽绒服 L 码',           4::SMALLINT, 499, 260, 12),
        (a, b, cat_fun,     '尤克里里 23 寸',             4::SMALLINT, 299, 150, 15),
        (d, a, cat_digital, '机械键盘腕托',               5::SMALLINT, 59,  40,  17),
        (b, c, cat_book,    'C Primer Plus 第六版',       3::SMALLINT, 89,  35,  19)
    ) AS t(seller, buyer, cat, title, cond, orig, price, ago)
    LOOP
        l := hxy.create_listing(r.seller, r.cat, r.title, '演示历史成交商品', r.cond, r.orig, r.price);
        o := hxy.place_order(l, r.buyer);
        PERFORM hxy.pay_order(o, r.buyer);
        PERFORM hxy.mark_order_delivered(o, r.seller);
        PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', r.buyer);
        history := history || ARRAY[o, r.ago];
    END LOOP;

    -- ---------- 在售商品
    PERFORM hxy.create_listing(a, cat_digital, 'iPad 第九代 64G 深空灰',
        '2023 年购入，一直贴膜带壳使用，电池健康 89%，附原装充电器。', 4::SMALLINT, 2499, 1450);
    PERFORM hxy.create_listing(b, cat_digital, '机械键盘 青轴 87 键',
        '换了静音键盘所以出，键帽无打油，送一套备用键帽。', 4::SMALLINT, 299, 160);
    PERFORM hxy.create_listing(c, cat_digital, 'Kindle Paperwhite 4',
        '看书神器，屏幕无划痕，带保护套。', 3::SMALLINT, 958, 420);
    PERFORM hxy.create_listing(d, cat_book, '数据结构（C 语言版）严蔚敏',
        '少量笔记，期末复习很好用。', 3::SMALLINT, 35, 15);
    PERFORM hxy.create_listing(a, cat_book, '考研英语真题 黄皮书 2026',
        '只做了前三年，后面全新。', 4::SMALLINT, 89, 40);
    PERFORM hxy.create_listing(e, cat_book, '概率论与数理统计 浙大第五版',
        '九成新，无笔记。', 4::SMALLINT, 42, 20);
    PERFORM hxy.create_listing(b, cat_life, '小熊电煮锅 1.2L',
        '宿舍可用的小功率，毕业清仓。', 4::SMALLINT, 129, 55);
    PERFORM hxy.create_listing(c, cat_life, '护眼台灯 无频闪',
        '三档调光，有轻微使用痕迹。', 3::SMALLINT, 159, 70);
    PERFORM hxy.create_listing(d, cat_sport, '迪卡侬山地自行车 27.5 寸',
        '骑了一年，刚换过刹车片，送车锁。', 3::SMALLINT, 1599, 680);
    PERFORM hxy.create_listing(e, cat_sport, '斯伯丁 7 号篮球',
        '室外球，气很足。', 3::SMALLINT, 199, 80);
    PERFORM hxy.create_listing(a, cat_cloth, '北面冲锋衣 M 码',
        '只穿过两次，尺码不合适。', 5::SMALLINT, 1299, 780);
    PERFORM hxy.create_listing(c, cat_fun, '雅马哈 F310 民谣吉他',
        '送调音器、变调夹和琴包。', 4::SMALLINT, 899, 450);

    -- ---------- 进行中的订单（演示各状态）
    -- 待交付：赵同学买了王同学的机械键盘
    SELECT listing_id INTO l FROM hxy.listing WHERE title = '机械键盘 青轴 87 键';
    o := hxy.place_order(l, d);
    PERFORM hxy.pay_order(o, d);
    -- 待收货：林同学买了陈同学的护眼台灯
    SELECT listing_id INTO l FROM hxy.listing WHERE title = '护眼台灯 无频闪';
    o := hxy.place_order(l, a);
    PERFORM hxy.pay_order(o, a);
    PERFORM hxy.mark_order_delivered(o, c);
    -- 待核实：周同学买了赵同学的数据结构教材后申请取消
    SELECT listing_id INTO l FROM hxy.listing WHERE title = '数据结构（C 语言版）严蔚敏';
    o := hxy.place_order(l, e);
    PERFORM hxy.pay_order(o, e);
    PERFORM hxy.open_order_review(o, 'BUYER_CANCEL_REQUEST', e);

    -- ---------- 收藏与估价记录
    INSERT INTO hxy.favorite (user_id, listing_id)
    SELECT a, listing_id FROM hxy.listing WHERE title IN ('Kindle Paperwhite 4', '雅马哈 F310 民谣吉他');
    INSERT INTO hxy.favorite (user_id, listing_id)
    SELECT d, listing_id FROM hxy.listing WHERE title = 'iPad 第九代 64G 深空灰';
    PERFORM hxy.create_valuation(a, cat_digital, 'AirPods Pro 二代', 4::SMALLINT, 1899);
    PERFORM hxy.create_valuation(a, cat_book, '算法导论 第三版', 3::SMALLINT, 128);

    -- ---------- 把历史数据分散到过去 20 天，让看板有真实的时间分布。
    -- 只用于演示数据：先让延迟约束立即检查，再临时关闭用户触发器，平移各时间字段后恢复。
    SET CONSTRAINTS ALL IMMEDIATE;
    ALTER TABLE hxy.trade_order DISABLE TRIGGER USER;
    ALTER TABLE hxy.point_transfer DISABLE TRIGGER USER;
    ALTER TABLE hxy.balance_ledger DISABLE TRIGGER USER;
    ALTER TABLE hxy.score_event DISABLE TRIGGER USER;
    ALTER TABLE hxy.listing DISABLE TRIGGER USER;
    ALTER TABLE hxy.price_history DISABLE TRIGGER USER;
    FOR i IN 1 .. array_length(history, 1) / 2 LOOP
        o := history[2 * i - 1];
        UPDATE hxy.trade_order
           SET created_at = created_at - make_interval(days => history[2 * i]::INT, hours => 30),
               payment_deadline_at = payment_deadline_at - make_interval(days => history[2 * i]::INT, hours => 30),
               paid_at = paid_at - make_interval(days => history[2 * i]::INT, hours => 29),
               delivered_at = delivered_at - make_interval(days => history[2 * i]::INT, hours => 6),
               auto_complete_at = auto_complete_at - make_interval(days => history[2 * i]::INT, hours => 6),
               completed_at = completed_at - make_interval(days => history[2 * i]::INT)
         WHERE order_id = o
        RETURNING listing_id INTO l;
        UPDATE hxy.point_transfer
           SET occurred_at = occurred_at - make_interval(days => history[2 * i]::INT,
                                                        hours => CASE event_type WHEN 'PAYMENT' THEN 29 ELSE 0 END)
         WHERE order_id = o;
        UPDATE hxy.score_event SET occurred_at = occurred_at - make_interval(days => history[2 * i]::INT)
         WHERE order_id = o;
        UPDATE hxy.listing
           SET created_at = created_at - make_interval(days => history[2 * i]::INT + 2),
               updated_at = updated_at - make_interval(days => history[2 * i]::INT)
         WHERE listing_id = l;
        UPDATE hxy.price_history SET changed_at = changed_at - make_interval(days => history[2 * i]::INT + 2)
         WHERE listing_id = l;
    END LOOP;
    -- 在售商品发布时间分散到最近 9 天；用户注册与初始积分发放提前到 30 天前
    UPDATE hxy.listing l2 SET created_at = l2.created_at - make_interval(days => (l2.listing_id % 9)::INT, hours => (l2.listing_id % 7)::INT),
                              updated_at = l2.updated_at - make_interval(days => (l2.listing_id % 9)::INT, hours => (l2.listing_id % 7)::INT)
     WHERE l2.status = 'ON_SALE';
    UPDATE hxy.price_history h SET changed_at = l2.created_at
      FROM hxy.listing l2 WHERE l2.listing_id = h.listing_id AND l2.status = 'ON_SALE';
    UPDATE hxy.app_user SET created_at = created_at - INTERVAL '30 days';
    UPDATE hxy.point_transfer SET occurred_at = occurred_at - INTERVAL '30 days' WHERE event_type = 'GRANT';
    ALTER TABLE hxy.trade_order ENABLE TRIGGER USER;
    ALTER TABLE hxy.point_transfer ENABLE TRIGGER USER;
    ALTER TABLE hxy.balance_ledger ENABLE TRIGGER USER;
    ALTER TABLE hxy.score_event ENABLE TRIGGER USER;
    ALTER TABLE hxy.listing ENABLE TRIGGER USER;
    ALTER TABLE hxy.price_history ENABLE TRIGGER USER;
END
$seed$;

COMMIT;
