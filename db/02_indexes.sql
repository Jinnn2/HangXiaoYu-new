-- 航小鱼：物理设计 —— 查询用索引
-- 主键、UNIQUE 约束会自动建立 B+ 树索引；01_schema.sql 中的部分唯一索引用于保证业务规则。
-- PostgreSQL 不会自动为外键列建索引，下面按实际查询补充。全部为默认的 B-tree 索引。

BEGIN;

-- 市场首页：按状态筛选、按发布时间倒序分页。
CREATE INDEX listing_status_created_idx ON hxy.listing (status, created_at DESC);
-- 分类浏览、估价时按分类统计成交样本。
CREATE INDEX listing_category_status_idx ON hxy.listing (category_id, status);
-- 卖家"我的商品"、订单视图联结卖家、信誉统计。
CREATE INDEX listing_seller_idx ON hxy.listing (seller_id);

-- 买家"我的订单"。
CREATE INDEX trade_order_buyer_idx ON hxy.trade_order (buyer_id, order_id DESC);
-- 商品详情页查询该商品的历史订单、删除商品前检查是否成交过。
CREATE INDEX trade_order_listing_idx ON hxy.trade_order (listing_id);
-- 定时任务：只索引需要扫描的那一小部分订单（部分索引）。
CREATE INDEX trade_order_payment_due_idx ON hxy.trade_order (payment_deadline_at)
    WHERE status = 'PENDING_PAYMENT';
CREATE INDEX trade_order_auto_complete_due_idx ON hxy.trade_order (auto_complete_at)
    WHERE status = 'PENDING_RECEIPT';
CREATE INDEX trade_order_delivery_due_idx ON hxy.trade_order (paid_at)
    WHERE status = 'PENDING_DELIVERY';
-- 估价：按完成时间取近期成交样本。
CREATE INDEX trade_order_completed_idx ON hxy.trade_order (completed_at)
    WHERE status = 'COMPLETED';

-- 账户流水页：某账户的全部明细。
CREATE INDEX balance_ledger_account_idx ON hxy.balance_ledger (account_id);

-- 账户汇总：某用户某类评分的合计。
CREATE INDEX score_event_user_type_idx ON hxy.score_event (user_id, score_type);

-- 商品详情页的价格走势。
CREATE INDEX price_history_listing_time_idx ON hxy.price_history (listing_id, changed_at);

-- 管理员核实列表：未处理的核实单按提交时间排序。
CREATE INDEX order_review_open_idx ON hxy.order_review (opened_at) WHERE resolved_at IS NULL;
CREATE INDEX order_review_order_idx ON hxy.order_review (order_id);

-- "我的收藏"按用户已由主键 (user_id, listing_id) 覆盖；商品被删除时按 listing_id 级联需要此索引。
CREATE INDEX favorite_listing_idx ON hxy.favorite (listing_id);

-- 估价历史。
CREATE INDEX valuation_requester_idx ON hxy.valuation (requester_id, created_at DESC);

COMMIT;
