-- 商品发布、修改、改价与价格历史、上下架、删除（含级联）、禁止再售、收藏。
DO $t$
DECLARE s BIGINT; b BIGINT; l BIGINT; l2 BIGINT; o BIGINT; h BIGINT;
BEGIN
    s := hxy_test.new_user('20001');
    b := hxy_test.new_user('20002');
    l := hxy.create_listing(s, 1, '  二手显示器 ', '24 寸', 4::SMALLINT, 999, 400);
    PERFORM hxy_test.ok((SELECT title FROM hxy.listing WHERE listing_id = l) = '二手显示器', '标题去除首尾空格');
    PERFORM hxy_test.ok((SELECT COUNT(*) FROM hxy.price_history
                          WHERE listing_id = l AND change_type = 'INITIAL' AND price_points = 400) = 1,
                        '触发器写入首次挂牌价格历史');

    h := hxy.reprice_listing(l, s, 350);
    PERFORM hxy_test.ok((SELECT price_points FROM hxy.price_history WHERE history_id = h) = 350
                        AND (SELECT change_type FROM hxy.price_history WHERE history_id = h) = 'REPRICE',
                        '改价追加 REPRICE 历史');
    PERFORM hxy_test.ok((SELECT current_price_points FROM hxy.listing WHERE listing_id = l) = 350, '当前价已更新');
    PERFORM hxy_test.fails(format('SELECT hxy.reprice_listing(%s, %s, 300)', l, b), '不是商品', '非卖家不能改价');
    PERFORM hxy_test.fails(format('SELECT hxy.reprice_listing(%s, %s, 350)', l, s), '相同', '价格不变时拒绝');
    PERFORM hxy_test.fails('UPDATE hxy.price_history SET price_points = 1', '不可修改', '价格历史不可修改');
    PERFORM hxy_test.fails('DELETE FROM hxy.price_history', '不可单独删除', '价格历史不可单独删除');
    PERFORM hxy_test.fails(format('UPDATE hxy.listing SET seller_id = %s WHERE listing_id = %s', b, l),
                           '卖家归属不可修改', '卖家归属不可修改');

    PERFORM hxy.update_listing_info(l, s, 2, '27 寸显示器', '更新描述', 3::SMALLINT, 1299, 'https://example.com/a.jpg');
    PERFORM hxy_test.ok((SELECT title = '27 寸显示器' AND category_id = 2 AND condition_level = 3
                           AND updated_at > created_at FROM hxy.listing WHERE listing_id = l),
                        '修改商品信息并更新 updated_at');

    -- 上下架
    PERFORM hxy.take_off_shelf(l, s);
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'OFF_SHELF', '下架');
    PERFORM hxy_test.fails(format('SELECT hxy.place_order(%s, %s)', l, b), '不是在售', '下架商品不能购买');
    PERFORM hxy.put_on_shelf(l, s);
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'ON_SALE', '重新上架');

    -- 收藏与级联删除
    INSERT INTO hxy.favorite (user_id, listing_id) VALUES (b, l);
    PERFORM hxy_test.fails(format('INSERT INTO hxy.favorite (user_id, listing_id) VALUES (%s, %s)', b, l),
                           'favorite_pkey', '同一商品不能重复收藏');
    PERFORM hxy_test.fails(format('SELECT hxy.delete_listing(%s, %s)', l, b), '不是商品', '非卖家不能删除');
    PERFORM hxy.delete_listing(l, s);
    PERFORM hxy_test.ok(NOT EXISTS (SELECT 1 FROM hxy.listing WHERE listing_id = l), '删除未成交商品');
    PERFORM hxy_test.ok(NOT EXISTS (SELECT 1 FROM hxy.price_history WHERE listing_id = l)
                        AND NOT EXISTS (SELECT 1 FROM hxy.favorite WHERE listing_id = l),
                        '价格历史与收藏随商品级联删除');

    -- 有订单的商品不能删除（函数检查 + 外键兜底）
    l2 := hxy.create_listing(s, 1, '有订单的商品', '', 4::SMALLINT, NULL, 30);
    o := hxy.place_order(l2, b);
    PERFORM hxy.cancel_unpaid_order(o, b);
    PERFORM hxy_test.fails(format('SELECT hxy.delete_listing(%s, %s)', l2, s), '只能下架不能删除',
                           '有订单记录的商品不能删除');
    PERFORM hxy_test.fails(format('DELETE FROM hxy.listing WHERE listing_id = %s', l2), 'foreign key',
                           '外键阻止直接删除有订单的商品');
    PERFORM hxy_test.fails(format('DELETE FROM hxy.trade_order WHERE order_id = %s', o), '不可删除',
                           '订单记录不可删除');

    -- 管理员禁止再售
    PERFORM hxy.set_relist_blocked(1, l2, TRUE);
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l2) = 'OFF_SHELF', '禁止再售时下架');
    PERFORM hxy_test.fails(format('SELECT hxy.put_on_shelf(%s, %s)', l2, s), '禁止再售', '禁止再售的商品不能上架');
    PERFORM hxy_test.fails(format('SELECT hxy.set_relist_blocked(%s, %s, FALSE)', s, l2), '不是有效的管理员',
                           '普通用户不能解除禁止');
END $t$;
