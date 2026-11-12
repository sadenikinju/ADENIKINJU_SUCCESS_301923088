-- =====================================================================
-- MIT 8103 - Advanced Database Systems Portfolio
-- Portfolio 1: Database Design and Modelling
-- Case Study: SwiftPay Fintech Platform
-- File: 01_schema.sql  (DDL: tables, keys, constraints)
-- Target: PostgreSQL 16
-- =====================================================================
--
-- This script creates the full relational schema for the SwiftPay
-- digital banking platform. Run with:  psql -d swiftpay -f 01_schema.sql
-- =====================================================================

DROP TABLE IF EXISTS notification, card, beneficiary,
                       transaction_log, transaction, account,
                       customer, branch, transaction_type
                       CASCADE;

-- ---------------------------------------------------------------------
-- 1. BRANCH  (Bank branch network)
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    branch_id      BIGSERIAL    PRIMARY KEY,
    branch_name    VARCHAR(100) NOT NULL,
    branch_code    CHAR(6)      UNIQUE NOT NULL,
    address        VARCHAR(200) NOT NULL,
    city           VARCHAR(50)  NOT NULL,
    region         VARCHAR(50),
    phone          VARCHAR(20),
    created_at     TIMESTAMPTZ  DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 2. CUSTOMER  (Account holder with KYC details)
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id    BIGSERIAL    PRIMARY KEY,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(100) UNIQUE NOT NULL,
    phone          VARCHAR(20)  UNIQUE NOT NULL,
    date_of_birth  DATE         NOT NULL,
    gender         CHAR(1)      CHECK (gender IN ('M','F','O')),
    national_id    VARCHAR(20)  UNIQUE NOT NULL,
    address        VARCHAR(200) NOT NULL,
    city           VARCHAR(50)  NOT NULL,
    country        VARCHAR(50)  DEFAULT 'Nigeria',
    kyc_status     VARCHAR(20)  DEFAULT 'PENDING'
                   CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED')),
    created_at     TIMESTAMPTZ  DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  DEFAULT NOW(),
    CONSTRAINT chk_customer_dob CHECK (date_of_birth < CURRENT_DATE - INTERVAL '16 years')
);

-- ---------------------------------------------------------------------
-- 3. ACCOUNT  (Bank account owned by a customer)
-- ---------------------------------------------------------------------
CREATE TABLE account (
    account_id     BIGSERIAL    PRIMARY KEY,
    account_number VARCHAR(14)  UNIQUE NOT NULL,
    customer_id    BIGINT       NOT NULL REFERENCES customer(customer_id),
    branch_id      BIGINT       REFERENCES branch(branch_id),
    account_type   VARCHAR(20)  NOT NULL
                   CHECK (account_type IN ('SAVINGS','CURRENT','FIXED')),
    opening_balance NUMERIC(15,2) NOT NULL DEFAULT 0.00,  -- balance at go-live (2026-09-01)
    balance        NUMERIC(15,2) NOT NULL DEFAULT 0.00,    -- = opening_balance + completed credits - debits
    currency       CHAR(3)      DEFAULT 'NGN',
    status         VARCHAR(15)  DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','DORMANT','CLOSED','FROZEN')),
    opened_at      TIMESTAMPTZ  DEFAULT NOW(),
    closed_at      TIMESTAMPTZ,
    -- Savings and fixed accounts cannot go negative.
    -- Current accounts are allowed an overdraft of up to 100,000 NGN.
    CONSTRAINT chk_balance_limit CHECK (
        (account_type IN ('SAVINGS','FIXED') AND balance >= 0)
        OR (account_type = 'CURRENT'        AND balance >= -100000)
    ),
    CONSTRAINT chk_closed_consistency CHECK (
        (status = 'CLOSED' AND closed_at IS NOT NULL)
        OR status <> 'CLOSED'
    )
);

-- ---------------------------------------------------------------------
-- 4. TRANSACTION_TYPE  (Reference / lookup table - normalisation)
-- ---------------------------------------------------------------------
CREATE TABLE transaction_type (
    type_id        SMALLSERIAL  PRIMARY KEY,
    type_name      VARCHAR(30)  NOT NULL,
    type_code      VARCHAR(10)  UNIQUE NOT NULL,
    description    TEXT
);

-- ---------------------------------------------------------------------
-- 5. TRANSACTION  (Money movement between two accounts)
-- ---------------------------------------------------------------------
CREATE TABLE transaction (
    transaction_id BIGSERIAL    PRIMARY KEY,
    reference_no   VARCHAR(20)  UNIQUE NOT NULL,
    from_account_id BIGINT      REFERENCES account(account_id),
    to_account_id   BIGINT      REFERENCES account(account_id),
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    currency       CHAR(3)      DEFAULT 'NGN',
    type_id        SMALLINT     NOT NULL REFERENCES transaction_type(type_id),
    status         VARCHAR(15)  DEFAULT 'PENDING'
                   CHECK (status IN ('PENDING','COMPLETED','FAILED','REVERSED')),
    channel        VARCHAR(20)
                   CHECK (channel IN ('WEB','MOBILE','ATM','POS','BRANCH','API','SYSTEM')),
    description    VARCHAR(200),
    initiated_at   TIMESTAMPTZ  DEFAULT NOW(),
    completed_at   TIMESTAMPTZ,
    reversal_of    BIGINT       REFERENCES transaction(transaction_id),
    -- A transaction must reference at least one account
    CONSTRAINT chk_at_least_one_account CHECK (
        from_account_id IS NOT NULL OR to_account_id IS NOT NULL
    ),
    -- Sender and receiver cannot be the same account
    CONSTRAINT chk_accounts_different CHECK (
        from_account_id IS NULL OR to_account_id IS NULL
        OR from_account_id <> to_account_id
    ),
    -- A COMPLETED transaction must have a completed_at timestamp
    CONSTRAINT chk_completed_ts CHECK (
        (status = 'COMPLETED' AND completed_at IS NOT NULL)
        OR status <> 'COMPLETED'
    )
);

-- ---------------------------------------------------------------------
-- 6. TRANSACTION_LOG  (Append-only audit trail for every txn event)
-- ---------------------------------------------------------------------
CREATE TABLE transaction_log (
    log_id         BIGSERIAL    PRIMARY KEY,
    transaction_id BIGINT       NOT NULL REFERENCES transaction(transaction_id) ON DELETE CASCADE,
    event_type     VARCHAR(30)  NOT NULL
                   CHECK (event_type IN ('INITIATED','AUTHORIZED','COMPLETED',
                                          'FAILED','REVERSED','LOCKED','UNLOCKED')),
    event_data     JSONB,
    actor          VARCHAR(50)  NOT NULL,           -- user / system / job name
    occurred_at    TIMESTAMPTZ  DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 7. BENEFICIARY  (Saved payee added by a customer)
-- ---------------------------------------------------------------------
CREATE TABLE beneficiary (
    beneficiary_id      BIGSERIAL    PRIMARY KEY,
    customer_id         BIGINT       NOT NULL REFERENCES customer(customer_id),
    beneficiary_account_id BIGINT    REFERENCES account(account_id),
    beneficiary_name    VARCHAR(100) NOT NULL,
    bank_code           VARCHAR(10),                 -- bank sort code (inter-bank)
    nickname            VARCHAR(50),
    added_at            TIMESTAMPTZ  DEFAULT NOW(),
    -- A customer cannot save the same beneficiary account twice
    CONSTRAINT uq_beneficiary_per_customer
        UNIQUE (customer_id, beneficiary_account_id)
);

-- ---------------------------------------------------------------------
-- 8. CARD  (Debit / credit card linked to a customer account)
-- ---------------------------------------------------------------------
CREATE TABLE card (
    card_id         BIGSERIAL    PRIMARY KEY,
    card_number_hash VARCHAR(64) UNIQUE NOT NULL,   -- store HASH only, never PAN
    customer_id     BIGINT       NOT NULL REFERENCES customer(customer_id),
    account_id      BIGINT       NOT NULL REFERENCES account(account_id),
    card_type       VARCHAR(10)  NOT NULL CHECK (card_type IN ('DEBIT','CREDIT')),
    expiry_date     DATE         NOT NULL,
    -- No CVV column: PCI DSS forbids storing the CVV after authorisation,
    -- even hashed.
    status          VARCHAR(15)  DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE','BLOCKED','EXPIRED','LOST')),
    issued_at       TIMESTAMPTZ  DEFAULT NOW()
    -- "expiry must be in the future" is NOT a CHECK constraint: a CHECK that
    -- uses CURRENT_DATE becomes false for old rows as time passes, and a
    -- pg_dump backup would then fail to restore. It is enforced by the
    -- trigger trg_card_expiry below, only when a card is issued or changed.
);

-- ---------------------------------------------------------------------
-- 9. NOTIFICATION  (Customer-facing messages)
-- ---------------------------------------------------------------------
CREATE TABLE notification (
    notification_id BIGSERIAL    PRIMARY KEY,
    customer_id     BIGINT       NOT NULL REFERENCES customer(customer_id),
    message         VARCHAR(500) NOT NULL,
    channel         VARCHAR(15)
                    CHECK (channel IN ('SMS','EMAIL','PUSH')),
    status          VARCHAR(15)  DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','SENT','DELIVERED','FAILED')),
    created_at      TIMESTAMPTZ  DEFAULT NOW(),
    sent_at         TIMESTAMPTZ
);

-- ---------------------------------------------------------------------
-- 10. BUSINESS-RULE TRIGGERS
-- ---------------------------------------------------------------------
-- (a) A card can only be issued / updated with a future expiry date.
CREATE OR REPLACE FUNCTION fn_card_expiry() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.expiry_date <= CURRENT_DATE THEN
        RAISE EXCEPTION 'Card expiry % must be in the future', NEW.expiry_date
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_card_expiry BEFORE INSERT OR UPDATE OF expiry_date ON card
    FOR EACH ROW EXECUTE FUNCTION fn_card_expiry();

-- (b) A reversal may only reverse a COMPLETED transaction, for the same
--     amount, in the opposite direction. Reversing a FAILED transaction
--     would credit money that never moved.
CREATE OR REPLACE FUNCTION fn_reversal_valid() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o transaction%ROWTYPE;
BEGIN
    IF NEW.reversal_of IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO o FROM transaction WHERE transaction_id = NEW.reversal_of;
    IF o.status NOT IN ('COMPLETED','REVERSED') THEN
        RAISE EXCEPTION 'Cannot reverse transaction % with status %', o.reference_no, o.status
              USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.amount <> o.amount
       OR NEW.from_account_id IS DISTINCT FROM o.to_account_id
       OR NEW.to_account_id   IS DISTINCT FROM o.from_account_id THEN
        RAISE EXCEPTION 'Reversal must move the same amount in the opposite direction'
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_reversal_valid BEFORE INSERT ON transaction
    FOR EACH ROW EXECUTE FUNCTION fn_reversal_valid();

-- =====================================================================
-- End of schema DDL
-- =====================================================================
