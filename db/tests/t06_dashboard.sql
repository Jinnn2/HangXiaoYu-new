-- 看板统计函数与视图。
DO $t$
DECLARE s BIGINT; b BIGINT; l BIGINT; o BIGINT; o2 BIGINT;
BEGIN
    s := hxy_test.new_user('70001', 0);
    b := hxy_test.new_user('70002', 300);
    l := hxy.create_listing(s, 1, '看板商品', '', 4::SMALLINT, 200, 80);
    o := hxy.place_order(l, b);
    PERFORM hxy_test.ok((SELECT action FROM hxy.v_order_todo WHERE order_id = o AND actor_id = b) = 'PAY',
                        '待付款订单出现在买家待办');
    PERFORM hxy.pay_order(o, b);
    PERFORM hxy_test.ok((SELECT action FROM hxy.v_order_todo WHERE order_id = o AND actor_id = s) = 'DELIVER',
                        '付款后出现在卖家待办（交付）');
    PERFORM hxy.mark_order_delivered(o, s);
    PERFORM hxy_test.ok((SELECT action FROM hxy.v_order_todo WHERE order_id = o AND actor_id = b) = 'CONFIRM',
                        '交付后出现在买家待办（确认收货）');
    PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', b);
    PERFORM hxy_test.ok(NOT EXISTS (SELECT 1 FROM hxy.v_order_todo WHERE order_id = o), '完成后待办清空');

    PERFORM hxy_test.ok((SELECT COUNT(*) FROM hxy.user_daily_flow(b, 30)) = 30, '每日收支返回 30 天');
    PERFORM hxy_test.ok((SELECT income = 300 AND spend = 80 AND closing_balance = 220
                           FROM hxy.user_daily_flow(b, 30) WHERE day = current_date),
                        '今日收入 300（注册发放）、支出 80、日终余额 220');
    PERFORM hxy_test.ok((SELECT closing_balance FROM hxy.user_daily_flow(b, 30) WHERE day = current_date - 1) = 0,
                        '昨日余额倒推为 0（注册前）');

    PERFORM hxy_test.ok((SELECT bought_count = 1 AND bought_points = 80 FROM hxy.user_trade_stats(b)), '买家统计');
    PERFORM hxy_test.ok((SELECT sold_count = 1 AND sold_points = 80 FROM hxy.user_trade_stats(s)), '卖家统计');

    o2 := hxy.place_order(hxy.create_listing(s, 1, '进行中商品', '', 4::SMALLINT, NULL, 10), b);
    PERFORM hxy_test.ok((SELECT active_buying FROM hxy.user_trade_stats(b)) = 1
                        AND (SELECT active_selling FROM hxy.user_trade_stats(s)) = 1, '进行中订单计数');

    PERFORM hxy_test.ok((SELECT completed_orders = 1 AND completed_volume = 80 AND new_orders = 2
                           FROM hxy.platform_daily_activity(14) WHERE day = current_date),
                        '平台今日成交 1 笔 80 积分、新订单 2 笔');
    PERFORM hxy_test.ok((SELECT deals = 1 AND volume = 80 FROM hxy.v_top_sellers WHERE seller_id = s), '卖家排行');
END $t$;
