-- =====================================================================
-- MIT 8103 - Portfolio 3: Transactions and Concurrency
-- Case Study: SwiftPay Fintech Platform
-- File: 01_transactions.sql
-- Target: PostgreSQL 16
-- =====================================================================
-- This file demonstrates ACID transaction control on the SwiftPay
-- schema: BEGIN / COMMIT / ROLLBACK, SAVEPOINT, conditional rollback
-- inside a stored procedure, and a transfer procedure that atomically
-- debits one account and credits another.
-- =====================================================================

-- =====================================================================
-- T1. Atomic intra-bank transfer (the canonical ACID example)
--     Either both legs land, or neither does.
-- =====================================================================
BEGIN;

-- Lock both rows up-front and in a consistent order (low id first)
-- to avoid deadlocks when two transfers run in opposite directions.
SELECT account_id FROM account
 WHERE account_number IN ('SP0001110001','SP0001110003')
 ORDER BY account_id
 FOR UPDATE;

UPDATE account SET balance = balance - 5000
 WHERE account_number = 'SP0001110001';

UPDATE account SET balance = balance + 5000
 WHERE account_number = 'SP0001110003';

INSERT INTO transaction (reference_no, from_account_id, to_account_id,
                         amount, type_id, status, channel, description,
                         initiated_at, completed_at)
VALUES ('TXN-20261105-DEMO01',
        (SELECT account_id FROM account WHERE account_number='SP0001110001'),
        (SELECT account_id FROM account WHERE account_number='SP0001110003'),
        5000, 1, 'COMPLETED', 'WEB', 'Demo atomic transfer',
        NOW(), NOW());

INSERT INTO transaction_log (transaction_id, event_type, event_data, actor)
VALUES (CURRVAL('transaction_transaction_id_seq'), 'COMPLETED',
        '{"demo":"atomic transfer"}'::jsonb, 'demo_user');

COMMIT;
-- ROLLBACK; would undo all four statements atomically.

-- =====================================================================
-- T2. Failed transfer + automatic rollback (insufficient funds)
-- =====================================================================
BEGIN;

SELECT balance FROM account WHERE account_number = 'SP0001110001' FOR UPDATE;

-- Attempt to withdraw more than the balance from a SAVINGS account.
-- The CHECK constraint chk_balance_limit (balance >= 0 for SAVINGS)
-- will raise SQLSTATE 23514 and abort the statement.
UPDATE account SET balance = balance - 99999999
 WHERE account_number = 'SP0001110001';

-- If we reach here, the constraint did not fire (unexpected).
INSERT INTO transaction (reference_no, from_account_id, to_account_id,
                         amount, type_id, status, channel, description)
VALUES ('TXN-20261105-DEMO02',
        (SELECT account_id FROM account WHERE account_number='SP0001110001'),
        NULL, 99999999, 3, 'COMPLETED', 'ATM', 'Will never persist');

COMMIT;
-- Expected: ERROR: new row for relation "account" violates check
-- constraint "chk_balance_limit"
-- The transaction is automatically rolled back by PostgreSQL.

-- =====================================================================
-- T3. SAVEPOINT - partial rollback inside a larger transaction
--     A multi-step batch where one step fails but we want to keep
--     the others.
-- =====================================================================
BEGIN;

INSERT INTO notification (customer_id, message, channel)
VALUES (1, 'Promotional: 5% cashback on bills this week', 'SMS');

SAVEPOINT sp_before_risky_insert;

-- Risky: insert a transfer that references a non-existent account (99999).
-- The FOREIGN KEY on from_account_id rejects it (SQLSTATE 23503) and the
-- whole transaction block becomes 'aborted' until we roll back to the savepoint.
-- (Plain SQL has no TRY/CATCH - EXCEPTION blocks only exist inside PL/pgSQL.)
INSERT INTO transaction (reference_no, from_account_id, to_account_id,
                         amount, type_id, status, completed_at)
VALUES ('TXN-20261105-DEMO03', 99999, 1, 1000, 1, 'COMPLETED', NOW());

ROLLBACK TO SAVEPOINT sp_before_risky_insert;

-- The notification INSERT survives because it was before the savepoint.
COMMIT;

-- =====================================================================
-- T4. Stored procedure for a safe, atomic transfer
--     Encapsulates the entire transfer logic + audit log in one
--     callable unit. The procedure always leaves the database in a
--     consistent state.
-- =====================================================================
CREATE OR REPLACE PROCEDURE sp_transfer_funds(
    p_from_account   VARCHAR,
    p_to_account     VARCHAR,
    p_amount         NUMERIC(15,2),
    p_description    VARCHAR,
    p_channel        VARCHAR DEFAULT 'WEB',
    INOUT p_reference VARCHAR DEFAULT NULL
) LANGUAGE plpgsql
AS $$
DECLARE
    v_from_id    BIGINT;
    v_to_id      BIGINT;
    v_from_type  VARCHAR;
    v_to_type    VARCHAR;
    v_from_bal   NUMERIC(15,2);
    v_to_bal     NUMERIC(15,2);
    v_ref        VARCHAR;
BEGIN
    -- 1. Generate a unique reference number
    -- 'TXN-' + YYMMDDHHMISS + 4-digit sequence = 20 chars (fits VARCHAR(20))
    v_ref := 'TXN-' || TO_CHAR(NOW(),'YYMMDDHH24MISS') ||
             LPAD(NEXTVAL('txn_ref_seq')::TEXT, 4, '0');

    -- 2. Lock both accounts in deterministic order (smaller id first)
    --    to avoid deadlocks between concurrent transfers.
    --    The PERFORM below takes BOTH row locks in ascending account_id
    --    order before anything else, so two opposite transfers (A->B and
    --    B->A) always queue on the same row instead of deadlocking.
    PERFORM 1 FROM account
     WHERE account_number IN (p_from_account, p_to_account)
     ORDER BY account_id
       FOR UPDATE;

    SELECT account_id, account_type, balance
      INTO v_from_id, v_from_type, v_from_bal
      FROM account
     WHERE account_number = p_from_account
       AND status = 'ACTIVE'
     FOR UPDATE;

    IF v_from_id IS NULL THEN
        RAISE EXCEPTION 'Source account not found or not active: %', p_from_account;
    END IF;

    SELECT account_id, account_type, balance
      INTO v_to_id, v_to_type, v_to_bal
      FROM account
     WHERE account_number = p_to_account
       AND status = 'ACTIVE'
     FOR UPDATE;

    IF v_to_id IS NULL THEN
        RAISE EXCEPTION 'Destination account not found or not active: %', p_to_account;
    END IF;

    -- 3. Business rule: cannot transfer to the same account
    IF v_from_id = v_to_id THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;

    -- 4. Business rule: amount must be positive
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;

    -- 5. Business rule: sufficient funds (allow overdraft for CURRENT accounts)
    IF v_from_type = 'SAVINGS' AND v_from_bal < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds in savings account';
    END IF;
    IF v_from_type = 'CURRENT' AND (v_from_bal - p_amount) < -100000 THEN
        RAISE EXCEPTION 'Overdraft limit exceeded';
    END IF;

    -- 6. Debit / Credit
    UPDATE account SET balance = balance - p_amount
     WHERE account_id = v_from_id;

    UPDATE account SET balance = balance + p_amount
     WHERE account_id = v_to_id;

    -- 7. Insert the transaction record
    INSERT INTO transaction (reference_no, from_account_id, to_account_id,
                             amount, type_id, status, channel,
                             description, initiated_at, completed_at)
    VALUES (v_ref, v_from_id, v_to_id, p_amount, 1,
            'COMPLETED', p_channel, p_description, NOW(), NOW());

    -- 8. Write the audit trail
    INSERT INTO transaction_log (transaction_id, event_type, event_data, actor)
    VALUES (CURRVAL('transaction_transaction_id_seq'), 'INITIATED',
            jsonb_build_object('amount', p_amount,
                               'from', p_from_account,
                               'to',   p_to_account),
            current_user);
    INSERT INTO transaction_log (transaction_id, event_type, event_data, actor)
    VALUES (CURRVAL('transaction_transaction_id_seq'), 'COMPLETED',
            jsonb_build_object('from_balance_after', v_from_bal - p_amount,
                               'to_balance_after',   v_to_bal   + p_amount),
            current_user);

    p_reference := v_ref;
END;
$$;

-- Helper sequence used by the procedure above
CREATE SEQUENCE IF NOT EXISTS txn_ref_seq START 1;

-- Call the procedure (inside an explicit transaction so the caller controls commit)
BEGIN;
CALL sp_transfer_funds('SP0001110001','SP0001110003', 7500.00,
                       'Procedure-driven demo transfer', 'MOBILE', NULL);
COMMIT;

-- =====================================================================
-- End of 01_transactions.sql
-- =====================================================================
