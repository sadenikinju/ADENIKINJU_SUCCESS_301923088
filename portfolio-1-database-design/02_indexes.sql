-- =====================================================================
-- MIT 8103 - Portfolio 1
-- File: 02_indexes.sql  (Indexes created AFTER schema & seed data)
-- Purpose: Optimise the most frequent read paths in SwiftPay.
--          Index choice rationale is documented in README.md.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Foreign-key support indexes (PostgreSQL does NOT auto-index FKs)
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_account_customer     ON account(customer_id);
CREATE INDEX IF NOT EXISTS idx_account_branch       ON account(branch_id);

CREATE INDEX IF NOT EXISTS idx_txn_from_account     ON transaction(from_account_id);
CREATE INDEX IF NOT EXISTS idx_txn_to_account       ON transaction(to_account_id);
CREATE INDEX IF NOT EXISTS idx_txn_type             ON transaction(type_id);
CREATE INDEX IF NOT EXISTS idx_txn_reversal         ON transaction(reversal_of);

CREATE INDEX IF NOT EXISTS idx_log_transaction      ON transaction_log(transaction_id);
CREATE INDEX IF NOT EXISTS idx_beneficiary_customer ON beneficiary(customer_id);
CREATE INDEX IF NOT EXISTS idx_beneficiary_account  ON beneficiary(beneficiary_account_id);
CREATE INDEX IF NOT EXISTS idx_card_customer        ON card(customer_id);
CREATE INDEX IF NOT EXISTS idx_card_account         ON card(account_id);
CREATE INDEX IF NOT EXISTS idx_notif_customer       ON notification(customer_id);

-- ---------------------------------------------------------------------
-- B. Customer login & KYC lookups
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_customer_email       ON customer(email);
CREATE INDEX IF NOT EXISTS idx_customer_phone       ON customer(phone);
CREATE INDEX IF NOT EXISTS idx_customer_kyc         ON customer(kyc_status);

-- ---------------------------------------------------------------------
-- C. Account-statement generation (the hottest read path)
--    Statement = "all transactions for account X within date range,
--                 newest first".
--    Composite index on (account_id, initiated_at DESC) lets PostgreSQL
--    satisfy the statement with an index-only range scan.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_from_acct_date
    ON transaction(from_account_id, initiated_at DESC);

CREATE INDEX IF NOT EXISTS idx_txn_to_acct_date
    ON transaction(to_account_id, initiated_at DESC);

-- ---------------------------------------------------------------------
-- D. Reference-number lookup (customer care / support)
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_reference         ON transaction(reference_no);

-- ---------------------------------------------------------------------
-- E. Reporting: status-by-date and type-by-date rollups
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_status_date
    ON transaction(status, initiated_at);

CREATE INDEX IF NOT EXISTS idx_txn_type_date
    ON transaction(type_id, initiated_at);

-- ---------------------------------------------------------------------
-- F. Compliance / fraud screening: high-value transactions
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_amount
    ON transaction(amount DESC);

-- ---------------------------------------------------------------------
-- G. PARTIAL INDEX  -  only COMPLETED transactions are ever queried
--    for balance recompute and statements. Skipping PENDING/FAILED rows
--    makes the index ~70% smaller and statements faster.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_completed_partial
    ON transaction(initiated_at DESC)
    WHERE status = 'COMPLETED';

-- ---------------------------------------------------------------------
-- H. COVERING INDEX  -  customer statement includes amount + type + ref
--    Include those columns so the statement is served entirely from
--    the index (Index-Only Scan), no heap fetches.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_from_covering
    ON transaction(from_account_id, initiated_at DESC)
    INCLUDE (amount, type_id, reference_no, status)
    WHERE status = 'COMPLETED';

CREATE INDEX IF NOT EXISTS idx_txn_to_covering
    ON transaction(to_account_id, initiated_at DESC)
    INCLUDE (amount, type_id, reference_no, status)
    WHERE status = 'COMPLETED';

-- ---------------------------------------------------------------------
-- I. Audit-trail timeline per transaction
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_log_txn_event_time
    ON transaction_log(transaction_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_log_event_time
    ON transaction_log(event_type, occurred_at DESC);

-- ---------------------------------------------------------------------
-- J. Expression index  -  frequently filter by date (not timestamp)
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_txn_initiated_date
    ON transaction (((initiated_at AT TIME ZONE 'Africa/Lagos')::date));

-- =====================================================================
-- End of indexes
-- =====================================================================
