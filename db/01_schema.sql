-- 航小鱼：校园二手交易与智能估价平台 —— 基本表定义（原生 PostgreSQL DDL）
-- 适用：PostgreSQL 16 及以上（开发环境 18）。在一个新建的专用数据库中首次执行。
-- 全部表放在 hxy schema 中；不包含 DROP，不会覆盖已有对象。
--
-- 实体（10 张基本表 + 1 张联系表）：
--   app_user 用户          category 商品分类       listing 商品
--   valuation 估价记录     trade_order 订单        point_account 积分账户
--   point_transfer 积分转移 balance_ledger 积分流水明细
--   price_history 价格历史  order_review 异常核实   score_event 评分事件
--   favorite 收藏（用户与商品的多对多联系）

BEGIN;

CREATE SCHEMA hxy;

-- pgcrypto 是受信任扩展，数据库所有者即可创建；用于在 SQL 中完成密码哈希与校验。
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------- 用户
CREATE TABLE hxy.app_user (
    user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_no    VARCHAR(20)  NOT NULL,
    display_name  VARCHAR(40)  NOT NULL,
    password_hash TEXT         NOT NULL,
    role          VARCHAR(10)  NOT NULL DEFAULT 'USER',
    status        VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT app_user_student_no_key UNIQUE (student_no),
    CONSTRAINT app_user_student_no_format CHECK (student_no ~ '^[0-9A-Za-z]{4,20}$'),
    CONSTRAINT app_user_name_not_blank CHECK (length(btrim(display_name)) > 0),
    CONSTRAINT app_user_role_check CHECK (role IN ('USER', 'ADMIN')),
    CONSTRAINT app_user_status_check CHECK (status IN ('ACTIVE', 'BANNED'))
);

-- ---------------------------------------------------------------- 分类
CREATE TABLE hxy.category (
    category_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(20) NOT NULL,
    sort_order  INTEGER     NOT NULL DEFAULT 0,
    CONSTRAINT category_name_key UNIQUE (name)
);

-- ---------------------------------------------------------------- 商品
CREATE TABLE hxy.listing (
    listing_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id             BIGINT       NOT NULL REFERENCES hxy.app_user (user_id),
    category_id           INTEGER      NOT NULL REFERENCES hxy.category (category_id),
    title                 VARCHAR(60)  NOT NULL,
    description           TEXT         NOT NULL DEFAULT '',
    condition_level       SMALLINT     NOT NULL,
    original_price_points BIGINT,
    current_price_points  BIGINT       NOT NULL,
    image_url             TEXT,
    status                VARCHAR(20)  NOT NULL DEFAULT 'ON_SALE',
    relist_blocked        BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT listing_title_not_blank CHECK (length(btrim(title)) > 0),
    -- 成色：5 全新/几乎全新，4 九成新，3 八成新，2 七成新，1 有明显瑕疵
    CONSTRAINT listing_condition_check CHECK (condition_level BETWEEN 1 AND 5),
    CONSTRAINT listing_original_price_check CHECK (original_price_points IS NULL OR original_price_points > 0),
    CONSTRAINT listing_price_check CHECK (current_price_points > 0),
    CONSTRAINT listing_status_check CHECK (status IN
        ('ON_SALE', 'PAYMENT_RESERVED', 'TRADING', 'RELIST_BUFFER', 'OFF_SHELF', 'SOLD'))
);

-- ---------------------------------------------------------------- 收藏（多对多联系）
CREATE TABLE hxy.favorite (
    user_id    BIGINT      NOT NULL REFERENCES hxy.app_user (user_id),
    listing_id BIGINT      NOT NULL REFERENCES hxy.listing (listing_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (user_id, listing_id)
);

-- ---------------------------------------------------------------- 估价记录
-- 记录用户某次提交的估价条件与当时的结果；不引用商品，避免与商品属性形成传递依赖。
CREATE TABLE hxy.valuation (
    valuation_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_id           BIGINT      NOT NULL REFERENCES hxy.app_user (user_id),
    category_id            INTEGER     NOT NULL REFERENCES hxy.category (category_id),
    item_name              VARCHAR(60) NOT NULL,
    condition_level        SMALLINT    NOT NULL,
    original_price_points  BIGINT      NOT NULL,
    suggested_price_points BIGINT      NOT NULL,
    low_price_points       BIGINT      NOT NULL,
    high_price_points      BIGINT      NOT NULL,
    sample_count           INTEGER     NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT valuation_condition_check CHECK (condition_level BETWEEN 1 AND 5),
    CONSTRAINT valuation_original_check CHECK (original_price_points > 0),
    CONSTRAINT valuation_range_check CHECK (
        0 < low_price_points AND low_price_points <= suggested_price_points
        AND suggested_price_points <= high_price_points),
    CONSTRAINT valuation_sample_check CHECK (sample_count >= 0)
);

-- ---------------------------------------------------------------- 积分账户
-- USER：每个用户一个；PLATFORM_ESCROW：平台托管，恰好一个；
-- PLATFORM_ISSUER：演示积分发行账户，恰好一个，余额为负，表示已发放的积分总额。
-- 由此所有账户余额之和恒为 0，每个余额都可以由流水重新计算。
CREATE TABLE hxy.point_account (
    account_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_type     VARCHAR(20) NOT NULL,
    user_id        BIGINT REFERENCES hxy.app_user (user_id),
    balance_points BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT point_account_owner_type_check CHECK (owner_type IN ('USER', 'PLATFORM_ESCROW', 'PLATFORM_ISSUER')),
    CONSTRAINT point_account_owner_shape CHECK (
        (owner_type = 'USER' AND user_id IS NOT NULL)
        OR (owner_type <> 'USER' AND user_id IS NULL)),
    CONSTRAINT point_account_balance_check CHECK (balance_points >= 0 OR owner_type = 'PLATFORM_ISSUER'),
    CONSTRAINT point_account_user_key UNIQUE (user_id)
);

CREATE UNIQUE INDEX point_account_one_platform_account
    ON hxy.point_account (owner_type) WHERE owner_type <> 'USER';

INSERT INTO hxy.point_account (owner_type) VALUES ('PLATFORM_ESCROW'), ('PLATFORM_ISSUER');

-- ---------------------------------------------------------------- 订单
CREATE TABLE hxy.trade_order (
    order_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    listing_id            BIGINT      NOT NULL REFERENCES hxy.listing (listing_id),
    buyer_id              BIGINT      NOT NULL REFERENCES hxy.app_user (user_id),
    price_snapshot_points BIGINT      NOT NULL,
    status                VARCHAR(20) NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL,
    payment_deadline_at   TIMESTAMPTZ NOT NULL,
    paid_at               TIMESTAMPTZ,
    delivered_at          TIMESTAMPTZ,
    auto_complete_at      TIMESTAMPTZ,
    completed_at          TIMESTAMPTZ,
    completion_method     VARCHAR(20),
    canceled_at           TIMESTAMPTZ,
    cancel_reason         VARCHAR(30),
    CONSTRAINT trade_order_price_check CHECK (price_snapshot_points > 0),
    CONSTRAINT trade_order_status_check CHECK (status IN
        ('PENDING_PAYMENT', 'PENDING_DELIVERY', 'PENDING_RECEIPT',
         'UNDER_REVIEW', 'COMPLETED', 'CANCELED', 'PAYMENT_EXPIRED')),
    CONSTRAINT trade_order_method_check CHECK (completion_method IN ('BUYER_CONFIRMED', 'AUTO')),
    CONSTRAINT trade_order_cancel_reason_check CHECK (cancel_reason IN
        ('BUYER_CANCEL_UNPAID', 'BUYER_CANCEL_REQUEST', 'NOT_RECEIVED', 'SELLER_DELIVERY_LATE')),
    CONSTRAINT trade_order_deadline_check CHECK (payment_deadline_at > created_at),
    CONSTRAINT trade_order_completion_together CHECK (
        (completed_at IS NULL) = (completion_method IS NULL)),
    CONSTRAINT trade_order_cancel_together CHECK (
        (canceled_at IS NULL) = (cancel_reason IS NULL)),
    CONSTRAINT trade_order_completed_shape CHECK (
        status <> 'COMPLETED' OR (paid_at IS NOT NULL AND delivered_at IS NOT NULL AND completed_at IS NOT NULL))
);

-- 历史订单可有多笔，但同一商品同时最多一笔有效订单（并发下单的最终防线）。
CREATE UNIQUE INDEX trade_order_one_active_per_listing
    ON hxy.trade_order (listing_id)
    WHERE status IN ('PENDING_PAYMENT', 'PENDING_DELIVERY', 'PENDING_RECEIPT', 'UNDER_REVIEW');

-- ---------------------------------------------------------------- 积分转移（一次转账事件）
-- GRANT 为注册时的初始积分发放，不对应订单；其余三类必须对应订单。
CREATE TABLE hxy.point_transfer (
    transfer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    BIGINT REFERENCES hxy.trade_order (order_id),
    event_type  VARCHAR(20) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT point_transfer_event_check CHECK (event_type IN ('GRANT', 'PAYMENT', 'SETTLEMENT', 'REFUND')),
    CONSTRAINT point_transfer_order_shape CHECK ((event_type = 'GRANT') = (order_id IS NULL)),
    CONSTRAINT point_transfer_order_event_key UNIQUE (order_id, event_type)
);

-- 一个订单的结算与退款只能二选一。
CREATE UNIQUE INDEX point_transfer_one_terminal_per_order
    ON hxy.point_transfer (order_id) WHERE event_type IN ('SETTLEMENT', 'REFUND');

-- ---------------------------------------------------------------- 积分流水明细（复式记账的一侧）
CREATE TABLE hxy.balance_ledger (
    ledger_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id  BIGINT NOT NULL REFERENCES hxy.point_transfer (transfer_id),
    account_id   BIGINT NOT NULL REFERENCES hxy.point_account (account_id),
    delta_points BIGINT NOT NULL,
    CONSTRAINT balance_ledger_delta_check CHECK (delta_points <> 0),
    CONSTRAINT balance_ledger_side_key UNIQUE (transfer_id, account_id)
);

-- ---------------------------------------------------------------- 价格历史（商品的弱实体）
CREATE TABLE hxy.price_history (
    history_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    listing_id   BIGINT      NOT NULL REFERENCES hxy.listing (listing_id) ON DELETE CASCADE,
    price_points BIGINT      NOT NULL,
    change_type  VARCHAR(10) NOT NULL,
    changed_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT price_history_price_check CHECK (price_points > 0),
    CONSTRAINT price_history_type_check CHECK (change_type IN ('INITIAL', 'REPRICE'))
);

CREATE UNIQUE INDEX price_history_one_initial_per_listing
    ON hxy.price_history (listing_id) WHERE change_type = 'INITIAL';

-- ---------------------------------------------------------------- 异常核实
CREATE TABLE hxy.order_review (
    review_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        BIGINT      NOT NULL REFERENCES hxy.trade_order (order_id),
    reason          VARCHAR(30) NOT NULL,
    previous_status VARCHAR(20) NOT NULL,
    opened_at       TIMESTAMPTZ NOT NULL,
    decision        VARCHAR(10),
    resolved_at     TIMESTAMPTZ,
    admin_id        BIGINT REFERENCES hxy.app_user (user_id),
    CONSTRAINT order_review_reason_check CHECK (reason IN
        ('BUYER_CANCEL_REQUEST', 'NOT_RECEIVED', 'SELLER_DELIVERY_LATE')),
    CONSTRAINT order_review_previous_check CHECK (previous_status IN ('PENDING_DELIVERY', 'PENDING_RECEIPT')),
    CONSTRAINT order_review_decision_check CHECK (decision IN ('CANCEL', 'CONTINUE')),
    CONSTRAINT order_review_resolution_together CHECK (
        (decision IS NULL AND resolved_at IS NULL AND admin_id IS NULL)
        OR (decision IS NOT NULL AND resolved_at IS NOT NULL AND admin_id IS NOT NULL))
);

CREATE UNIQUE INDEX order_review_one_open_per_order
    ON hxy.order_review (order_id) WHERE resolved_at IS NULL;

-- ---------------------------------------------------------------- 评分事件
-- 买家奖励分与卖家信誉分的变动记录，与可消费的演示积分完全分开。
CREATE TABLE hxy.score_event (
    score_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id       BIGINT      NOT NULL REFERENCES hxy.trade_order (order_id),
    user_id        BIGINT      NOT NULL REFERENCES hxy.app_user (user_id),
    score_type     VARCHAR(20) NOT NULL,
    reason         VARCHAR(30) NOT NULL,
    delta_score    INTEGER     NOT NULL,
    occurred_at    TIMESTAMPTZ NOT NULL,
    operator_id    BIGINT REFERENCES hxy.app_user (user_id),
    CONSTRAINT score_event_type_check CHECK (score_type IN ('BUYER_REWARD', 'SELLER_REPUTATION')),
    CONSTRAINT score_event_reason_check CHECK (reason IN ('COMPLETION', 'VERIFIED_DELIVERY_LATE')),
    CONSTRAINT score_event_once_key UNIQUE (order_id, score_type, reason)
);

COMMIT;
