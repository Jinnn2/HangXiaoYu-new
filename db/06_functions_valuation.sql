-- 航小鱼：智能估价存储过程（参考饰品交易市场的"同款比价"思路）
--
-- 估价按三层逐级回退：
--   ① 同款：同分类、名称相似度 ≥ 0.3 的近 180 天成交。像饰品市场一样直接看同款的成交价，
--      按成色折算到目标成色后取中位数；权重 w = n / (n + 2)，其余部分用"原价 × 成色经验折旧率"。
--   ② 同分类：没有同款成交时，用同分类成交的"成交价 ÷ 原价"比率（按成色折算）的中位数；
--      权重 w = n / (n + 5)。
--   ③ 成色经验值：几乎全新 0.85、九成新 0.70、八成新 0.55、七成新 0.40、有瑕疵 0.25。
-- 同时给出同款"在售"参考：在售件数、最低价、中位价（饰品市场的"在售最低价"）。
--
-- 名称相似度：把名称切成片段——英文 / 数字按整词，中文按相邻两字——
-- 两个名称共有片段数 ÷ 全部不同片段数（Jaccard 系数）。

CREATE OR REPLACE FUNCTION hxy.condition_base_ratio(p_condition SMALLINT)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_condition WHEN 5 THEN 0.85 WHEN 4 THEN 0.70 WHEN 3 THEN 0.55
                            WHEN 2 THEN 0.40 WHEN 1 THEN 0.25 END::NUMERIC;
$$;

-- 名称切片："小米手环 8 NFC版" → {小米, 米手, 手环, 8, nfc, 版}
CREATE OR REPLACE FUNCTION hxy.name_tokens(p_name TEXT)
RETURNS TEXT[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(array_agg(DISTINCT tok), '{}')
      FROM (
        SELECT m[1] AS tok
          FROM regexp_matches(lower(COALESCE(p_name, '')), '([a-z0-9]+)', 'g') AS m
        UNION ALL
        SELECT substr(r.run, i, 2)
          FROM (SELECT x[1] AS run
                  FROM regexp_matches(COALESCE(p_name, ''), '([一-鿿]+)', 'g') AS x) r,
               generate_series(1, GREATEST(char_length(r.run) - 1, 1)) AS i
      ) t
     WHERE tok <> '';
$$;

CREATE OR REPLACE FUNCTION hxy.name_similarity(p_a TEXT, p_b TEXT)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN cardinality(a) = 0 OR cardinality(b) = 0 THEN 0
                ELSE round((SELECT COUNT(*) FROM unnest(a) t WHERE t = ANY (b))::NUMERIC
                           / (SELECT COUNT(*) FROM (SELECT unnest(a) UNION SELECT unnest(b)) u), 3)
           END
      FROM (SELECT hxy.name_tokens(p_a) AS a, hxy.name_tokens(p_b) AS b) s;
$$;

-- 估价参考的成交记录：同分类近 180 天成交，标出是否同款，并给出按成色折算到目标成色后的价格。
CREATE OR REPLACE FUNCTION hxy.valuation_samples(
    p_category_id INTEGER,
    p_item_name   TEXT,
    p_condition   SMALLINT
) RETURNS TABLE (order_id BIGINT, title TEXT, condition_level SMALLINT,
                 original_price_points BIGINT, price_points BIGINT, completed_at TIMESTAMPTZ,
                 similarity NUMERIC, same_item BOOLEAN, adjusted_price NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT o.order_id, l.title::TEXT, l.condition_level, l.original_price_points,
           o.price_snapshot_points, o.completed_at,
           hxy.name_similarity(p_item_name, l.title) AS sim,
           hxy.name_similarity(p_item_name, l.title) >= 0.3,
           round(o.price_snapshot_points * hxy.condition_base_ratio(p_condition)
                 / hxy.condition_base_ratio(l.condition_level), 1)
      FROM hxy.trade_order o
      JOIN hxy.listing l ON l.listing_id = o.listing_id
     WHERE o.status = 'COMPLETED'
       AND o.completed_at >= clock_timestamp() - INTERVAL '180 days'
       AND l.category_id = p_category_id
     ORDER BY o.completed_at DESC;
$$;

-- 同款在售商品（名称相似度 ≥ 0.3），按价格从低到高。
CREATE OR REPLACE FUNCTION hxy.same_item_listings(p_category_id INTEGER, p_item_name TEXT)
RETURNS TABLE (listing_id BIGINT, title TEXT, condition_level SMALLINT,
               current_price_points BIGINT, created_at TIMESTAMPTZ, similarity NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT l.listing_id, l.title::TEXT, l.condition_level, l.current_price_points, l.created_at,
           hxy.name_similarity(p_item_name, l.title)
      FROM hxy.listing l
     WHERE l.status = 'ON_SALE'
       AND l.category_id = p_category_id
       AND hxy.name_similarity(p_item_name, l.title) >= 0.3
     ORDER BY l.current_price_points, l.listing_id;
$$;

-- 只计算不保存。旧版只有前三个参数，新增的物品名称参数可省略（省略时跳过同款层）。
DROP FUNCTION IF EXISTS hxy.estimate_price(INTEGER, SMALLINT, BIGINT);
CREATE OR REPLACE FUNCTION hxy.estimate_price(
    p_category_id    INTEGER,
    p_condition      SMALLINT,
    p_original_price BIGINT,
    p_item_name      TEXT DEFAULT NULL,
    OUT suggested_price_points BIGINT,
    OUT low_price_points       BIGINT,
    OUT high_price_points      BIGINT,
    OUT sample_count           INTEGER,
    OUT market_ratio           NUMERIC,
    OUT basis                  TEXT,
    OUT same_item_count        INTEGER,
    OUT same_item_median       BIGINT,
    OUT listing_count          INTEGER,
    OUT listing_min            BIGINT,
    OUT listing_median         BIGINT
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base    NUMERIC;
    v_anchor  NUMERIC;   -- 原价 × 成色经验折旧率
    v_p25     NUMERIC;
    v_p50     NUMERIC;
    v_p75     NUMERIC;
    v_value   NUMERIC;
    v_w       NUMERIC;
    v_name    TEXT := NULLIF(btrim(p_item_name), '');
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
    v_anchor := p_original_price * v_base;
    same_item_count := 0;
    listing_count := 0;

    -- 在售参考
    IF v_name IS NOT NULL THEN
        SELECT COUNT(*), min(current_price_points),
               round(percentile_cont(0.5) WITHIN GROUP (ORDER BY current_price_points))
          INTO listing_count, listing_min, listing_median
          FROM hxy.same_item_listings(p_category_id, v_name);
    END IF;

    -- ① 同款成交：直接用成交价（按成色折算到目标成色）
    IF v_name IS NOT NULL THEN
        SELECT COUNT(*),
               percentile_cont(0.25) WITHIN GROUP (ORDER BY adjusted_price),
               percentile_cont(0.5)  WITHIN GROUP (ORDER BY adjusted_price),
               percentile_cont(0.75) WITHIN GROUP (ORDER BY adjusted_price)
          INTO same_item_count, v_p25, v_p50, v_p75
          FROM hxy.valuation_samples(p_category_id, v_name, p_condition)
         WHERE same_item;
    END IF;

    IF same_item_count > 0 THEN
        basis := 'SAME_ITEM';
        sample_count := same_item_count;
        same_item_median := round(v_p50);
        v_w := same_item_count::NUMERIC / (same_item_count + 2);
        v_value := v_w * v_p50 + (1 - v_w) * v_anchor;
        market_ratio := round(v_p50 / p_original_price, 4);
        suggested_price_points := GREATEST(1, round(v_value));
        IF same_item_count >= 3 THEN
            low_price_points  := GREATEST(1, round(LEAST(v_p25, v_value * 0.9)));
            high_price_points := round(GREATEST(v_p75, v_value * 1.1));
        ELSE
            low_price_points  := GREATEST(1, round(v_value * 0.85));
            high_price_points := round(v_value * 1.15);
        END IF;
    ELSE
        -- ② 同分类成交：用"成交价 ÷ 原价"的比率
        SELECT COUNT(*),
               percentile_cont(0.25) WITHIN GROUP (ORDER BY r),
               percentile_cont(0.5)  WITHIN GROUP (ORDER BY r),
               percentile_cont(0.75) WITHIN GROUP (ORDER BY r)
          INTO sample_count, v_p25, v_p50, v_p75
          FROM (SELECT adjusted_price / original_price_points AS r
                  FROM hxy.valuation_samples(p_category_id, v_name, p_condition)
                 WHERE original_price_points IS NOT NULL) s;
        basis := CASE WHEN sample_count > 0 THEN 'CATEGORY' ELSE 'DEFAULT' END;
        market_ratio := round(v_p50, 4);
        v_w := sample_count::NUMERIC / (sample_count + 5);
        v_value := CASE WHEN sample_count = 0 THEN v_anchor
                        ELSE p_original_price * (v_w * v_p50 + (1 - v_w) * v_base) END;
        suggested_price_points := GREATEST(1, round(v_value));
        IF sample_count >= 3 THEN
            low_price_points  := GREATEST(1, round(LEAST(p_original_price * v_p25, v_value * 0.9)));
            high_price_points := round(GREATEST(p_original_price * v_p75, v_value * 1.1));
        ELSE
            low_price_points  := GREATEST(1, round(v_value * 0.85));
            high_price_points := round(v_value * 1.15);
        END IF;
    END IF;
    low_price_points  := LEAST(low_price_points, suggested_price_points);
    high_price_points := GREATEST(high_price_points, suggested_price_points);
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
    SELECT * INTO e FROM hxy.estimate_price(p_category_id, p_condition, p_original_price, p_item_name);
    INSERT INTO hxy.valuation (requester_id, category_id, item_name, condition_level,
                               original_price_points, suggested_price_points,
                               low_price_points, high_price_points, sample_count, basis)
    VALUES (p_requester_id, p_category_id, btrim(p_item_name), p_condition, p_original_price,
            e.suggested_price_points, e.low_price_points, e.high_price_points, e.sample_count, e.basis)
    RETURNING valuation_id INTO v_id;
    RETURN v_id;
END $$;
