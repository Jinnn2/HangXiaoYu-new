-- 下单 → 付款托管 → 交付 → 确认收货 / 自动完成；超时、取消、状态机。
DO $t$
DECLARE s BIGINT; b BIGINT; c BIGINT; l BIGINT; o BIGINT; o2 BIGINT;
BEGIN
    s := hxy_test.new_user('30001', 0);
    b := hxy_test.new_user('30002', 500);
    c := hxy_test.new_user('30003', 50);
    l := hxy.create_listing(s, 1, '台灯', '', 4::SMALLINT, 200, 100);

    PERFORM hxy_test.fails(format('SELECT hxy.place_order(%s, %s)', l, s), '不能购买自己', '卖家不能买自己的商品');
    PERFORM hxy_test.fails(format('SELECT hxy.place_order(%s, %s, 90)', l, b), '价格已变为 100',
                           '页面价格与当前价不一致时要求重新确认');
    o := hxy.place_order(l, b, 100);
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o) = 'PENDING_PAYMENT'
                        AND (SELECT status FROM hxy.listing WHERE listing_id = l) = 'PAYMENT_RESERVED',
                        '下单后订单待付款、商品支付占用');
    PERFORM hxy_test.ok((SELECT payment_deadline_at - created_at FROM hxy.trade_order WHERE order_id = o)
                        = INTERVAL '5 minutes', '付款期限为 5 分钟');
    PERFORM hxy_test.fails(format('SELECT hxy.place_order(%s, %s)', l, c), '已被有效订单占用', '占用期间他人不能下单');
    PERFORM hxy_test.fails(format('SELECT hxy.reprice_listing(%s, %s, 80)', l, s), '不能改价', '占用期间不能改价');
    PERFORM hxy_test.fails(format('SELECT hxy.pay_order(%s, %s)', o, c), '只有订单', '非买家不能付款');

    PERFORM hxy.pay_order(o, b);
    PERFORM hxy_test.ok(hxy_test.balance(b) = 400, '付款后买家余额 400');
    PERFORM hxy_test.ok((SELECT escrow_balance FROM hxy.v_platform_stats) = 100, '托管账户 100');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'TRADING', '商品交易中');
    PERFORM hxy_test.fails(format('SELECT hxy.pay_order(%s, %s)', o, b), '不能付款', '重复付款被拒绝');
    PERFORM hxy_test.fails(format('SELECT hxy.complete_order(%s, %L, %s)', o, 'BUYER_CONFIRMED', b),
                           '不允许结算', '未交付不能确认收货');

    PERFORM hxy.mark_order_delivered(o, s);
    PERFORM hxy_test.ok((SELECT auto_complete_at - delivered_at FROM hxy.trade_order WHERE order_id = o)
                        = INTERVAL '24 hours', '交付后 24 小时自动完成');
    PERFORM hxy_test.fails(format('SELECT hxy.complete_order(%s, %L)', o, 'AUTO'), '尚未到自动完成时间',
                           '未到期不能自动完成');
    PERFORM hxy_test.fails(format('SELECT hxy.complete_order(%s, %L, %s)', o, 'BUYER_CONFIRMED', s),
                           '只有订单', '卖家不能替买家确认');
    PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', b);
    PERFORM hxy_test.ok(hxy_test.balance(s) = 100 AND hxy_test.balance(b) = 400, '结算后卖家得 100');
    PERFORM hxy_test.ok((SELECT escrow_balance FROM hxy.v_platform_stats) = 0, '托管清零');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'SOLD', '商品已售');
    PERFORM hxy_test.ok((SELECT buyer_reward_points FROM hxy.v_user_account_summary WHERE user_id = b) = 1
                        AND (SELECT seller_reputation FROM hxy.v_user_account_summary WHERE user_id = s) = 81,
                        '买家奖励 +1、卖家信誉 81');
    PERFORM hxy_test.fails(format('SELECT hxy.complete_order(%s, %L, %s)', o, 'BUYER_CONFIRMED', b),
                           '不允许结算', '重复确认不会重复结算');
    PERFORM hxy_test.fails(format('UPDATE hxy.trade_order SET cancel_reason = NULL WHERE order_id = %s', o),
                           '已结束', '已完成订单不可再修改');
    PERFORM hxy_test.ok((SELECT COUNT(*) FROM hxy.balance_ledger b2 JOIN hxy.point_transfer t USING (transfer_id)
                          WHERE t.order_id = o) = 4, '一笔成交共 4 条流水（付款 2 + 结算 2）');

    -- 余额不足
    l := hxy.create_listing(s, 1, '贵重商品', '', 5::SMALLINT, 999, 300);
    o2 := hxy.place_order(l, c);
    PERFORM hxy_test.fails(format('SELECT hxy.pay_order(%s, %s)', o2, c), '积分不足', '余额不足不能付款');
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o2) = 'PENDING_PAYMENT'
                        AND hxy_test.balance(c) = 50, '余额不足时订单仍待付款、未扣分');
    PERFORM hxy_test.ok(hxy.cancel_unpaid_order(o2, c) = 'CANCELED', '买家取消未付款订单');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'ON_SALE', '取消后商品立即在售');

    -- 付款超时：到期后不能付款；任务释放；下单时顺带清理
    o2 := hxy.place_order(l, b);
    PERFORM hxy_test.shift_order_times(o2, INTERVAL '6 minutes');
    PERFORM hxy_test.fails(format('SELECT hxy.pay_order(%s, %s)', o2, b), '超过付款截止时间', '超时不能付款');
    PERFORM hxy_test.ok(hxy.expire_unpaid_orders() = 1, '到期任务处理 1 笔');
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o2) = 'PAYMENT_EXPIRED'
                        AND (SELECT status FROM hxy.listing WHERE listing_id = l) = 'ON_SALE', '超时订单释放商品');
    o2 := hxy.place_order(l, b);
    PERFORM hxy_test.shift_order_times(o2, INTERVAL '6 minutes');
    o := hxy.place_order(l, c);
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o2) = 'PAYMENT_EXPIRED',
                        '他人下单时先清理已过期占用');

    -- 自动完成
    l := hxy.create_listing(s, 2, '自动完成测试', '', 3::SMALLINT, 100, 40);
    o := hxy.place_order(l, b);
    PERFORM hxy.pay_order(o, b);
    PERFORM hxy.mark_order_delivered(o, s);
    PERFORM hxy_test.shift_order_times(o, INTERVAL '25 hours');
    PERFORM hxy_test.ok((SELECT auto_completed FROM hxy.run_scheduled_tasks()) = 1, '定时任务自动完成 1 笔');
    PERFORM hxy_test.ok((SELECT completion_method FROM hxy.trade_order WHERE order_id = o) = 'AUTO',
                        '完成方式记为 AUTO 而非买家确认');

    -- 状态机：不允许跳过付款直接完成
    l := hxy.create_listing(s, 2, '状态机测试', '', 3::SMALLINT, 100, 40);
    o := hxy.place_order(l, b);
    PERFORM hxy_test.fails(format('UPDATE hxy.trade_order SET status = %L WHERE order_id = %s', 'PENDING_RECEIPT', o),
                           '不允许从 PENDING_PAYMENT 变为 PENDING_RECEIPT', '状态机拒绝非法转换');
    PERFORM hxy_test.fails(format('UPDATE hxy.trade_order SET price_snapshot_points = 1 WHERE order_id = %s', o),
                           '不可修改', '价格快照不可修改');

    PERFORM hxy_test.ok(hxy_test.books_balanced(), '交易流程结束后账目平衡');
END $t$;
