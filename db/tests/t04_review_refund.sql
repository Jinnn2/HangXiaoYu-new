-- 异常核实：买家申请取消、未收到反馈、卖家超时未交付；退款、重新上架缓冲期。
DO $t$
DECLARE s BIGINT; b BIGINT; l BIGINT; o BIGINT; r BIGINT;
BEGIN
    s := hxy_test.new_user('40001', 0);
    b := hxy_test.new_user('40002', 500);

    -- 1. 买家申请取消 → 管理员同意 → 原额退款，商品进入缓冲期
    l := hxy.create_listing(s, 1, '耳机', '', 4::SMALLINT, 300, 120);
    o := hxy.place_order(l, b);
    PERFORM hxy.pay_order(o, b);
    PERFORM hxy_test.fails(format('SELECT hxy.open_order_review(%s, %L, %s)', o, 'BUYER_CANCEL_REQUEST', s),
                           '仅待交付订单的买家', '卖家不能替买家申请取消');
    r := hxy.open_order_review(o, 'BUYER_CANCEL_REQUEST', b);
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o) = 'UNDER_REVIEW', '订单进入待核实');
    PERFORM hxy_test.fails(format('SELECT hxy.mark_order_delivered(%s, %s)', o, s), '不允许交付', '核实期间不能交付');
    PERFORM hxy_test.fails(format('SELECT hxy.resolve_order_review(%s, %s, %L)', r, b, 'CANCEL'),
                           '不是有效的管理员', '普通用户不能处理核实');
    PERFORM hxy.resolve_order_review(r, 1, 'CANCEL');
    PERFORM hxy_test.ok(hxy_test.balance(b) = 500, '退款后买家余额恢复 500');
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o) = 'CANCELED'
                        AND (SELECT cancel_reason FROM hxy.trade_order WHERE order_id = o) = 'BUYER_CANCEL_REQUEST',
                        '订单已取消并记录原因');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'RELIST_BUFFER', '商品进入重新上架缓冲期');
    PERFORM hxy_test.ok((SELECT buyer_reward_points FROM hxy.v_user_account_summary WHERE user_id = b) = 0,
                        '取消订单不给买家奖励');
    PERFORM hxy_test.fails(format('SELECT hxy.place_order(%s, %s)', l, b), '不是在售', '缓冲期内不能购买');
    PERFORM hxy_test.ok(hxy.release_relist_buffers() = 0, '缓冲期未满不自动上架');
    PERFORM hxy_test.shift_order_times(o, INTERVAL '25 hours');
    PERFORM hxy_test.ok(hxy.release_relist_buffers() = 1, '缓冲期满自动恢复在售');
    PERFORM hxy_test.ok((SELECT status FROM hxy.listing WHERE listing_id = l) = 'ON_SALE', '商品在售');

    -- 2. 未收到反馈 → 管理员认定已交付、继续 → 重新计算 24 小时
    o := hxy.place_order(l, b);
    PERFORM hxy.pay_order(o, b);
    PERFORM hxy.mark_order_delivered(o, s);
    PERFORM hxy_test.shift_order_times(o, INTERVAL '20 hours');
    r := hxy.open_order_review(o, 'NOT_RECEIVED', b);
    PERFORM hxy_test.ok((SELECT auto_completed FROM hxy.run_scheduled_tasks()) = 0, '核实期间不会自动结算');
    PERFORM hxy.resolve_order_review(r, 1, 'CONTINUE');
    PERFORM hxy_test.ok((SELECT status FROM hxy.trade_order WHERE order_id = o) = 'PENDING_RECEIPT'
                        AND (SELECT auto_complete_at > clock_timestamp() + INTERVAL '23 hours'
                               FROM hxy.trade_order WHERE order_id = o),
                        '恢复待收货并从核实结束起重新计 24 小时');
    PERFORM hxy.complete_order(o, 'BUYER_CONFIRMED', b);
    PERFORM hxy_test.ok(hxy_test.balance(s) = 120, '最终结算给卖家');
    PERFORM hxy_test.fails(format('SELECT hxy.open_order_review(%s, %L, %s)', o, 'NOT_RECEIVED', b),
                           '仅自动完成期限前', '完成后不能再反馈未收到');

    -- 3. 卖家 48 小时未交付 → 系统发起核实 → 管理员确认违约并取消 → 退款 + 信誉 −10
    l := hxy.create_listing(s, 1, '迟交商品', '', 4::SMALLINT, 300, 100);
    o := hxy.place_order(l, b);
    PERFORM hxy.pay_order(o, b);
    PERFORM hxy_test.ok(hxy.open_late_delivery_reviews() = 0, '未满 48 小时不发起核实');
    PERFORM hxy_test.shift_order_times(o, INTERVAL '49 hours');
    PERFORM hxy_test.fails(format('SELECT hxy.mark_order_delivered(%s, %s)', o, s), '48 小时',
                           '超时后卖家不能直接标记交付');
    PERFORM hxy_test.ok((SELECT late_reviews FROM hxy.run_scheduled_tasks()) = 1, '定时任务发起超时核实');
    SELECT review_id INTO r FROM hxy.order_review WHERE order_id = o AND resolved_at IS NULL;
    PERFORM hxy_test.ok((SELECT delivery_late_evidence FROM hxy.v_open_reviews WHERE review_id = r),
                        '核实列表显示超时证据');
    PERFORM hxy.resolve_order_review(r, 1, 'CANCEL', TRUE);
    PERFORM hxy_test.ok((SELECT seller_reputation FROM hxy.v_user_account_summary WHERE user_id = s) = 71,
                        '卖家信誉 81 − 10 = 71');
    PERFORM hxy_test.ok((SELECT operator_id FROM hxy.score_event
                          WHERE order_id = o AND reason = 'VERIFIED_DELIVERY_LATE') = 1, '处罚记录操作的管理员');
    PERFORM hxy_test.fails(format('SELECT hxy.resolve_order_review(%s, 1, %L)', r, 'CANCEL'), '已处理',
                           '同一核实单不能处理两次');

    PERFORM hxy_test.ok(hxy_test.books_balanced(), '核实与退款后账目平衡');
END $t$;
