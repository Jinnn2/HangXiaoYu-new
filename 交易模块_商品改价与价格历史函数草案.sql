-- 航小鱼交易模块：在售商品改价并追加价格历史。
-- 仅适用于独立演示库的 user_stub/listing_stub；正式商品接口待小组确认。
-- 一个 SELECT 调用在 PostgreSQL 中作为一个原子事务执行。

CREATE OR REPLACE FUNCTION trade_demo.reprice_listing(
    p_listing_id BIGINT,
    p_seller_id BIGINT,
    p_new_price BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
AS $reprice$
DECLARE
    v_listing trade_demo.listing_stub%ROWTYPE;
    v_history_id BIGINT;
BEGIN
    IF p_new_price IS NULL OR p_new_price <= 0 THEN
        RAISE EXCEPTION '新挂牌价格必须是正整数积分';
    END IF;

    SELECT * INTO v_listing FROM trade_demo.listing_stub
     WHERE listing_id = p_listing_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION '商品 % 不存在', p_listing_id; END IF;
    IF v_listing.seller_id <> p_seller_id THEN
        RAISE EXCEPTION '用户 % 不是商品 % 的卖家', p_seller_id, p_listing_id;
    END IF;
    IF v_listing.status <> 'ON_SALE' THEN
        RAISE EXCEPTION '商品 % 目前不是在售状态，不能改价', p_listing_id;
    END IF;
    IF v_listing.current_price_points = p_new_price THEN
        RAISE EXCEPTION '商品 % 的新价格与当前价格相同', p_listing_id;
    END IF;
    IF EXISTS (
        SELECT 1 FROM trade_demo.trade_order
         WHERE listing_id = p_listing_id
           AND status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY',
                          'PENDING_RECEIPT', 'UNDER_REVIEW')
    ) THEN
        RAISE EXCEPTION '商品 % 有有效订单，不能改价', p_listing_id;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM trade_demo.price_history
         WHERE listing_id = p_listing_id AND change_type = 'INITIAL'
    ) THEN
        RAISE EXCEPTION '商品 % 缺少首次挂牌价格历史', p_listing_id;
    END IF;

    UPDATE trade_demo.listing_stub
       SET current_price_points = p_new_price
     WHERE listing_id = p_listing_id;
    INSERT INTO trade_demo.price_history
        (listing_id, price_points, change_type, changed_at)
    VALUES (p_listing_id, p_new_price, 'REPRICE', clock_timestamp())
    RETURNING history_id INTO v_history_id;
    RETURN v_history_id;
END
$reprice$;

-- 示例：SELECT trade_demo.reprice_listing(商品编号, 卖家编号, 新价格);
-- 每次成功改价只新增一条 REPRICE；旧历史和已有订单价格快照不变。
