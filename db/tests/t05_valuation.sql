-- 智能估价：无样本时按成色基准；有成交样本后向市场价靠拢；估价记录的增删。
DO $t$
DECLARE s BIGINT; b BIGINT; l BIGINT; o BIGINT; v BIGINT; e RECORD; i INT;
BEGIN
    s := hxy_test.new_user('50001', 0);
    b := hxy_test.new_user('50002', 5000);

    SELECT * INTO e FROM hxy.estimate_price(1, 4::SMALLINT, 1000);
    PERFORM hxy_test.ok(e.sample_count = 0 AND e.suggested_price_points = 700,
                        '无样本时 九成新 = 原价 × 0.70');
    PERFORM hxy_test.ok(e.low_price_points < e.suggested_price_points
                        AND e.suggested_price_points < e.high_price_points, '给出价格区间');
    PERFORM hxy_test.fails('SELECT * FROM hxy.estimate_price(1, 9::SMALLINT, 100)', '成色必须', '成色范围校验');
    PERFORM hxy_test.fails('SELECT * FROM hxy.estimate_price(999, 3::SMALLINT, 100)', '分类 999 不存在', '分类校验');

    -- 制造 5 笔"九成新以 4 折成交"的样本
    FOR i IN 1..5 LOOP
        l := hxy.create_listing(s, 1, '样本' || i, '', 4::SMALLINT, 1000, 400);
        o := hxy.place_order(l, b);
        PERFORM hxy.pay_order(o, b);
        PERFORM hxy.mark_order_delivered(o, s);
        PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', b);
    END LOOP;
    SELECT * INTO e FROM hxy.estimate_price(1, 4::SMALLINT, 1000);
    -- w = 5/10 = 0.5；比率 = 0.5×0.40 + 0.5×0.70 = 0.55
    PERFORM hxy_test.ok(e.sample_count = 5 AND e.market_ratio = 0.4 AND e.suggested_price_points = 550,
                        '有 5 个样本时建议价 = 原价 × (0.5×市场 0.40 + 0.5×基准 0.70) = 550');
    SELECT * INTO e FROM hxy.estimate_price(2, 4::SMALLINT, 1000);
    PERFORM hxy_test.ok(e.sample_count = 0, '其他分类不受影响');
    SELECT * INTO e FROM hxy.estimate_price(1, 5::SMALLINT, 1000);
    PERFORM hxy_test.ok(e.suggested_price_points > 550, '成色更好估价更高');

    v := hxy.create_valuation(b, 1, '某耳机', 4::SMALLINT, 1000);
    PERFORM hxy_test.ok((SELECT suggested_price_points FROM hxy.valuation WHERE valuation_id = v) = 550,
                        '保存估价记录');
    DELETE FROM hxy.valuation WHERE valuation_id = v AND requester_id = b;
    PERFORM hxy_test.ok(NOT EXISTS (SELECT 1 FROM hxy.valuation WHERE valuation_id = v), '删除估价记录');

    -- ---------- 同款比价
    PERFORM hxy_test.ok(hxy.name_tokens('小米手环 8 NFC版') @> ARRAY['小米', '米手', '手环', '8', 'nfc'],
                        '名称切片：中文相邻两字、英文数字整词');
    PERFORM hxy_test.ok(hxy.name_similarity('小米手环 8', '小米手环 8 NFC 版') >= 0.3
                        AND hxy.name_similarity('小米手环 8', '小米蓝牙耳机') < 0.3, '相似度区分同款与非同款');
    FOR i IN 1..3 LOOP
        l := hxy.create_listing(s, 1, '索尼 WH1000XM4 耳机 ' || i, '', 4::SMALLINT, NULL, 900 + i * 50);
        o := hxy.place_order(l, b);
        PERFORM hxy.pay_order(o, b);
        PERFORM hxy.mark_order_delivered(o, s);
        PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', b);
    END LOOP;
    PERFORM hxy.create_listing(s, 1, '索尼 WH1000XM4 耳机 在售', '', 4::SMALLINT, NULL, 980);
    SELECT * INTO e FROM hxy.estimate_price(1, 4::SMALLINT, 2299, '索尼 WH1000XM4 耳机');
    -- 同款中位数 1000，w = 3/5；锚点 2299×0.70 = 1609.3 → 0.6×1000 + 0.4×1609.3 = 1243.7
    PERFORM hxy_test.ok(e.basis = 'SAME_ITEM' AND e.same_item_count = 3 AND e.same_item_median = 1000
                        AND e.suggested_price_points = 1244, '有同款成交时按同款估价：0.6×1000 + 0.4×1609.3 ≈ 1244');
    PERFORM hxy_test.ok(e.listing_count = 1 AND e.listing_min = 980, '给出同款在售件数与最低价');
    SELECT * INTO e FROM hxy.estimate_price(1, 4::SMALLINT, 2299, '完全不同的东西');
    PERFORM hxy_test.ok(e.basis = 'CATEGORY' AND e.same_item_count = 0, '没有同款时回退到同分类');
    SELECT * INTO e FROM hxy.estimate_price(2, 4::SMALLINT, 100, '索尼耳机');
    PERFORM hxy_test.ok(e.basis = 'DEFAULT' AND e.suggested_price_points = 70, '分类没有成交时回退到成色经验值');
    PERFORM hxy_test.ok((SELECT COUNT(*) FILTER (WHERE same_item) FROM hxy.valuation_samples(1, '索尼 WH1000XM4 耳机', 4::SMALLINT)) = 3,
                        '成交记录中标出 3 笔同款');
    v := hxy.create_valuation(b, 1, '索尼 WH1000XM4 耳机', 4::SMALLINT, 2299);
    PERFORM hxy_test.ok((SELECT basis FROM hxy.valuation WHERE valuation_id = v) = 'SAME_ITEM', '估价记录保存估价依据');
END $t$;
