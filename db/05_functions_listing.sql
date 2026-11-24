-- 航小鱼：商品模块存储过程
-- 价格历史由触发器 T3 写入，这里只修改 listing.current_price_points。

CREATE OR REPLACE FUNCTION hxy.create_listing(
    p_seller_id      BIGINT,
    p_category_id    INTEGER,
    p_title          TEXT,
    p_description    TEXT,
    p_condition      SMALLINT,
    p_original_price BIGINT,
    p_price          BIGINT,
    p_image_url      TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT;
BEGIN
    PERFORM hxy.assert_active_user(p_seller_id);
    INSERT INTO hxy.listing (seller_id, category_id, title, description, condition_level,
                             original_price_points, current_price_points, image_url)
    VALUES (p_seller_id, p_category_id, btrim(p_title), COALESCE(p_description, ''),
            p_condition, p_original_price, p_price, NULLIF(btrim(p_image_url), ''))
    RETURNING listing_id INTO v_id;
    RETURN v_id;
END $$;

-- 锁定商品并确认操作人是卖家，返回锁住的行。
CREATE OR REPLACE FUNCTION hxy.lock_own_listing(p_listing_id BIGINT, p_seller_id BIGINT)
RETURNS hxy.listing
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
BEGIN
    SELECT * INTO v FROM hxy.listing WHERE listing_id = p_listing_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '商品 % 不存在', p_listing_id; END IF;
    IF v.seller_id <> p_seller_id THEN
        RAISE EXCEPTION '用户 % 不是商品 % 的卖家', p_seller_id, p_listing_id;
    END IF;
    RETURN v;
END $$;

-- 修改商品描述信息（不含价格）。交易进行中或已售出的商品不能修改。
CREATE OR REPLACE FUNCTION hxy.update_listing_info(
    p_listing_id     BIGINT,
    p_seller_id      BIGINT,
    p_category_id    INTEGER,
    p_title          TEXT,
    p_description    TEXT,
    p_condition      SMALLINT,
    p_original_price BIGINT,
    p_image_url      TEXT
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
BEGIN
    v := hxy.lock_own_listing(p_listing_id, p_seller_id);
    IF v.status NOT IN ('ON_SALE', 'OFF_SHELF', 'RELIST_BUFFER') THEN
        RAISE EXCEPTION '商品 % 正在交易或已售出，不能修改', p_listing_id;
    END IF;
    UPDATE hxy.listing
       SET category_id = p_category_id, title = btrim(p_title),
           description = COALESCE(p_description, ''), condition_level = p_condition,
           original_price_points = p_original_price, image_url = NULLIF(btrim(p_image_url), '')
     WHERE listing_id = p_listing_id;
END $$;

-- 改价：仅在售且无有效订单时允许；返回新价格历史编号。
CREATE OR REPLACE FUNCTION hxy.reprice_listing(p_listing_id BIGINT, p_seller_id BIGINT, p_new_price BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
    v_history_id BIGINT;
BEGIN
    IF p_new_price IS NULL OR p_new_price <= 0 THEN
        RAISE EXCEPTION '新价格必须是正整数积分';
    END IF;
    v := hxy.lock_own_listing(p_listing_id, p_seller_id);
    IF v.status NOT IN ('ON_SALE', 'OFF_SHELF') THEN
        RAISE EXCEPTION '商品 % 当前状态不能改价', p_listing_id;
    END IF;
    IF v.current_price_points = p_new_price THEN
        RAISE EXCEPTION '新价格与当前价格相同';
    END IF;
    UPDATE hxy.listing SET current_price_points = p_new_price WHERE listing_id = p_listing_id;
    SELECT max(history_id) INTO v_history_id FROM hxy.price_history WHERE listing_id = p_listing_id;
    RETURN v_history_id;
END $$;

-- 卖家下架：在售或缓冲期 → 下架（"继续下架"也走这里）。
CREATE OR REPLACE FUNCTION hxy.take_off_shelf(p_listing_id BIGINT, p_seller_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
BEGIN
    v := hxy.lock_own_listing(p_listing_id, p_seller_id);
    IF v.status NOT IN ('ON_SALE', 'RELIST_BUFFER') THEN
        RAISE EXCEPTION '商品 % 当前状态不能下架', p_listing_id;
    END IF;
    UPDATE hxy.listing SET status = 'OFF_SHELF' WHERE listing_id = p_listing_id;
END $$;

-- 卖家上架：下架或缓冲期 → 在售。管理员禁止再售的商品不能上架。
CREATE OR REPLACE FUNCTION hxy.put_on_shelf(p_listing_id BIGINT, p_seller_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
BEGIN
    PERFORM hxy.assert_active_user(p_seller_id);
    v := hxy.lock_own_listing(p_listing_id, p_seller_id);
    IF v.status NOT IN ('OFF_SHELF', 'RELIST_BUFFER') THEN
        RAISE EXCEPTION '商品 % 当前状态不能上架', p_listing_id;
    END IF;
    IF v.relist_blocked THEN
        RAISE EXCEPTION '商品 % 已被管理员禁止再售', p_listing_id;
    END IF;
    UPDATE hxy.listing SET status = 'ON_SALE' WHERE listing_id = p_listing_id;
END $$;

-- 删除商品：只允许删除从未产生过订单的商品；价格历史与收藏随之级联删除。
-- 有订单的商品由外键（RESTRICT）在数据库层面阻止删除，保证交易记录可追溯。
CREATE OR REPLACE FUNCTION hxy.delete_listing(p_listing_id BIGINT, p_seller_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v hxy.listing%ROWTYPE;
BEGIN
    v := hxy.lock_own_listing(p_listing_id, p_seller_id);
    IF EXISTS (SELECT 1 FROM hxy.trade_order WHERE listing_id = p_listing_id) THEN
        RAISE EXCEPTION '商品 % 已有订单记录，只能下架不能删除', p_listing_id;
    END IF;
    DELETE FROM hxy.listing WHERE listing_id = p_listing_id;
END $$;

-- 管理员禁止 / 允许再售。
CREATE OR REPLACE FUNCTION hxy.set_relist_blocked(p_admin_id BIGINT, p_listing_id BIGINT, p_blocked BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM hxy.assert_admin(p_admin_id);
    UPDATE hxy.listing
       SET relist_blocked = p_blocked,
           status = CASE WHEN p_blocked AND status IN ('ON_SALE', 'RELIST_BUFFER')
                         THEN 'OFF_SHELF' ELSE status END
     WHERE listing_id = p_listing_id;
    IF NOT FOUND THEN RAISE EXCEPTION '商品 % 不存在', p_listing_id; END IF;
END $$;

-- 定时任务：重新上架缓冲期满 24 小时、未禁止再售、卖家可用、无有效订单的商品自动恢复在售。
CREATE OR REPLACE FUNCTION hxy.release_relist_buffers(p_limit INTEGER DEFAULT 100)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_count INTEGER;
BEGIN
    WITH due AS (
        SELECT l.listing_id
          FROM hxy.listing l
          JOIN hxy.app_user u ON u.user_id = l.seller_id AND u.status = 'ACTIVE'
         WHERE l.status = 'RELIST_BUFFER'
           AND NOT l.relist_blocked
           AND (SELECT max(o.canceled_at) FROM hxy.trade_order o
                 WHERE o.listing_id = l.listing_id) + INTERVAL '24 hours' <= clock_timestamp()
           AND NOT EXISTS (SELECT 1 FROM hxy.trade_order o
                            WHERE o.listing_id = l.listing_id
                              AND o.status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY',
                                               'PENDING_RECEIPT', 'UNDER_REVIEW'))
         ORDER BY l.listing_id
         FOR UPDATE OF l SKIP LOCKED
         LIMIT p_limit
    )
    UPDATE hxy.listing l SET status = 'ON_SALE'
      FROM due WHERE l.listing_id = due.listing_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;
