-- 航小鱼：智能估价存储过程
-- 思路：用平台上同类商品的真实成交价估计"成交价 / 原价"的比率，再结合成色给出建议价与区间。
--   1. 成色基准折旧率（经验值）：5→0.85  4→0.70  3→0.55  2→0.40  1→0.25
--   2. 市场样本：近 180 天同分类、原价已知的已完成订单，
--      把每笔样本的成交比率按成色折算到目标成色：ratio × 基准率(目标成色) / 基准率(样本成色)
--   3. 样本越多越信任市场：权重 w = n / (n + 5)，最终比率 = w × 市场中位数 + (1 − w) × 基准率
--   4. 区间取样本 25%～75% 分位数与最终比率 ±10% 中较宽者（样本不足 3 笔时取 ±15%）

CREATE OR REPLACE FUNCTION hxy.condition_base_ratio(p_condition SMALLINT)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_condition WHEN 5 THEN 0.85 WHEN 4 THEN 0.70 WHEN 3 THEN 0.55
                            WHEN 2 THEN 0.40 WHEN 1 THEN 0.25 END::NUMERIC;
$$;

-- 只计算不保存，供发布商品页面实时参考。
CREATE OR REPLACE FUNCTION hxy.estimate_price(
    p_category_id    INTEGER,
    p_condition      SMALLINT,
    p_original_price BIGINT,
    OUT suggested_price_points BIGINT,
    OUT low_price_points       BIGINT,
    OUT high_price_points      BIGINT,
    OUT sample_count           INTEGER,
    OUT market_ratio           NUMERIC
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base  NUMERIC;
    v_p25   NUMERIC;
    v_p75   NUMERIC;
    v_ratio NUMERIC;
    v_w     NUMERIC;
BEGIN
    IF p_condition IS NULL OR p_condition NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION '成色必须在 1~5 之间';
    END IF;
    IF p_original_price IS NULL OR p_original_price <= 0 THEN
        RAISE EXCEPTION '原价必须是正整数';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hxy.category WHERE category_id = p_category_id) THEN
        RAISE EXCEPTION '分类 % 不存在', p_category_id;
    END IF;
    v_base := hxy.condition_base_ratio(p_condition);

    SELECT COUNT(*),
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY adj),
           percentile_cont(0.25) WITHIN GROUP (ORDER BY adj),
           percentile_cont(0.75) WITHIN GROUP (ORDER BY adj)
      INTO sample_count, market_ratio, v_p25, v_p75
      FROM (
        SELECT o.price_snapshot_points::NUMERIC / l.original_price_points
               * v_base / hxy.condition_base_ratio(l.condition_level) AS adj
          FROM hxy.trade_order o
          JOIN hxy.listing l ON l.listing_id = o.listing_id
         WHERE o.status = 'COMPLETED'
           AND o.completed_at >= clock_timestamp() - INTERVAL '180 days'
           AND l.category_id = p_category_id
           AND l.original_price_points IS NOT NULL
      ) s;

    v_w := sample_count::NUMERIC / (sample_count + 5);
    v_ratio := CASE WHEN sample_count = 0 THEN v_base
                    ELSE v_w * market_ratio + (1 - v_w) * v_base END;
    suggested_price_points := GREATEST(1, round(p_original_price * v_ratio));
    IF sample_count >= 3 THEN
        low_price_points  := GREATEST(1, round(p_original_price * LEAST(v_p25, v_ratio * 0.9)));
        high_price_points := GREATEST(suggested_price_points, round(p_original_price * GREATEST(v_p75, v_ratio * 1.1)));
    ELSE
        low_price_points  := GREATEST(1, round(p_original_price * v_ratio * 0.85));
        high_price_points := GREATEST(suggested_price_points, round(p_original_price * v_ratio * 1.15));
    END IF;
    low_price_points := LEAST(low_price_points, suggested_price_points);
    market_ratio := round(market_ratio, 4);
END $$;

-- 估价并保存一条估价记录，返回记录编号。
CREATE OR REPLACE FUNCTION hxy.create_valuation(
    p_requester_id   BIGINT,
    p_category_id    INTEGER,
    p_item_name      TEXT,
    p_condition      SMALLINT,
    p_original_price BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    e    RECORD;
    v_id BIGINT;
BEGIN
    PERFORM hxy.assert_active_user(p_requester_id);
    SELECT * INTO e FROM hxy.estimate_price(p_category_id, p_condition, p_original_price);
    INSERT INTO hxy.valuation (requester_id, category_id, item_name, condition_level,
                               original_price_points, suggested_price_points,
                               low_price_points, high_price_points, sample_count)
    VALUES (p_requester_id, p_category_id, btrim(p_item_name), p_condition, p_original_price,
            e.suggested_price_points, e.low_price_points, e.high_price_points, e.sample_count)
    RETURNING valuation_id INTO v_id;
    RETURN v_id;
END $$;
