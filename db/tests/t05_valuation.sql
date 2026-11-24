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
END $t$;
