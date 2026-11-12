-- =====================================================================
-- MIT 8103 - Portfolio 3: Isolation Levels & Concurrency
-- File: 02_concurrency.sql
-- =====================================================================
-- Demonstrates the four ANSI SQL isolation levels on the SwiftPay
-- `account` table, the anomalies each one permits or prevents, and
-- two real-world concurrency problems for a banking system:
--
--   * Lost update when two tellers adjust the same account
--   * Deadlock when two transfers run in opposite directions
--
-- Each demo is written as TWO concurrent sessions (Session A / B).
-- Open two psql terminals to run them side by side, or use pgAdmin's
-- parallel query tool. The expected interleaving is shown as comments.
-- =====================================================================

-- =====================================================================
-- C1. READ UNCOMMITTED  ->  PostgreSQL maps this to READ COMMITTED.
--     Dirty read is NOT possible in PostgreSQL. Demonstrated for
--     completeness.
-- =====================================================================
-- Session A
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
UPDATE account SET balance = balance + 50000
 WHERE account_number = 'SP0001110001';
-- Session B (separate connection)
-- BEGIN ISOLATION LEVEL READ UNCOMMITTED;
-- SELECT balance FROM account WHERE account_number = 'SP0001110001';
--   -> Returns the OLD balance. PostgreSQL never exposes uncommitted rows.
-- Session A
ROLLBACK;


-- =====================================================================
-- C2. READ COMMITTED (default)  ->  Non-repeatable READ
--     Session A reads balance, Session B updates and commits,
--     Session A reads again - gets a different value.
-- =====================================================================
-- Session A
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM account WHERE account_number = 'SP0001110001';  -- returns: 215000 (or whatever the current value is)

-- Session B (concurrent)
-- BEGIN;
-- UPDATE account SET balance = balance + 10000
--  WHERE account_number = 'SP0001110001';
-- COMMIT;

-- Session A: read the same row again
SELECT balance FROM account WHERE account_number = 'SP0001110001';  -- returns: 225000 (different!)
COMMIT;
-- ANOMALY: Non-repeatable read - the same query returned different
-- values inside the same transaction.


-- =====================================================================
-- C3. REPEATABLE READ  ->  Prevents non-repeatable read,
--     but in PostgreSQL it ALSO prevents phantom reads (stronger
--     than the ANSI spec). Snapshot isolation is used.
-- =====================================================================
-- Session A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM account WHERE account_number = 'SP0001110001';  -- snapshot taken

-- Session B
-- BEGIN;
-- UPDATE account SET balance = balance + 10000
--  WHERE account_number = 'SP0001110001';
-- COMMIT;

-- Session A: same query again
SELECT balance FROM account WHERE account_number = 'SP0001110001';  -- returns the ORIGINAL value (snapshot)
COMMIT;
-- NO anomaly - both reads returned the same value.


-- =====================================================================
-- C4. SERIALIZABLE  ->  Prevents all anomalies including write skew.
--     Two concurrent transfers that together would overdraw the
--     account are detected at COMMIT time and one is aborted.
-- =====================================================================
-- Setup: reset a SAVINGS account to a known low balance
UPDATE account SET balance = 5000
 WHERE account_number = 'SP0001110006';

-- Session A
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT balance FROM account WHERE account_number = 'SP0001110006';  -- 5000
-- Session B
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SELECT balance FROM account WHERE account_number = 'SP0001110006';  -- 5000
-- Both sessions believe there are 5000 available
-- Session A
UPDATE account SET balance = balance - 4000
 WHERE account_number = 'SP0001110006';   -- would leave 1000
-- Session B
-- UPDATE account SET balance = balance - 4000
--  WHERE account_number = 'SP0001110006';   -- would leave 1000 - but blocked
-- Session A
COMMIT;
-- Session B
-- COMMIT;
--   ERROR: could not serialize access due to read/write dependencies
--   among transactions
--   DETAIL: Reason code: Canceled on identification as a pivot during
--   write conflict.
-- The SERIALIZABLE scheduler aborts Session B because the dependency
-- graph is not serialisable in any order.


-- =====================================================================
-- C5. LOST UPDATE  (the classic banking bug)
--     Two tellers read the balance, both compute "balance + 1000",
--     both write back. Without locking, one update is lost.
--
--     Variant A: NAIVE (loses an update) - using READ COMMITTED
--                without row locking
--     Variant B: SAFE - using SELECT ... FOR UPDATE
-- =====================================================================

-- --- Variant A: NAIVE (will lose one update) -------------------------
-- Session A and B both read at the same time, both add 1000
-- Session A
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance INTO v_a FROM account WHERE account_number = 'SP0001110001';
-- Session B
-- BEGIN;
-- SELECT balance INTO v_b FROM account WHERE account_number = 'SP0001110001';
-- Session A
UPDATE account SET balance = v_a + 1000 WHERE account_number = 'SP0001110001';
COMMIT;
-- Session B
-- UPDATE account SET balance = v_b + 1000 WHERE account_number = 'SP0001110001';
-- COMMIT;
-- Result: balance increased by 1000 instead of 2000 - LOST UPDATE.

-- --- Variant B: SAFE - using SELECT ... FOR UPDATE -------------------
-- Session A
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM account WHERE account_number = 'SP0001110001' FOR UPDATE;
--   -> row lock acquired
-- Session B
-- BEGIN;
-- SELECT balance FROM account WHERE account_number = 'SP0001110001' FOR UPDATE;
--   -> BLOCKS until Session A commits or rolls back
-- Session A
UPDATE account SET balance = balance + 1000 WHERE account_number = 'SP0001110001';
COMMIT;
-- Session B is now unblocked, reads the NEW balance, adds 1000
--   UPDATE ...
--   COMMIT;
-- Result: balance increased by 2000 - both updates preserved.


-- =====================================================================
-- C6. DEADLOCK  -  two transfers in opposite directions
--     A locks account 1 then waits for account 2.
--     B locks account 2 then waits for account 1.
--     PostgreSQL detects the cycle within ~1s and aborts one
--     transaction with SQLSTATE 40P01.
-- =====================================================================
-- Session A
BEGIN;
UPDATE account SET balance = balance - 1000 WHERE account_number = 'SP0001110001';
-- Session B (concurrent)
-- BEGIN;
-- UPDATE account SET balance = balance - 1000 WHERE account_number = 'SP0001110003';
-- Session A
UPDATE account SET balance = balance + 1000 WHERE account_number = 'SP0001110003';  -- blocks
-- Session B
-- UPDATE account SET balance = balance + 1000 WHERE account_number = 'SP0001110001';  -- blocks
-- Within ~1 second, PostgreSQL aborts one of the two:
--   ERROR: deadlock detected
--   DETAIL: Process waits for ShareLock on transaction ... held by ...
-- FIX: always lock accounts in ascending account_id order (see the
--      sp_transfer_funds procedure in 01_transactions.sql).


-- =====================================================================
-- C7. OPTIMISTIC CONCURRENCY CONTROL  -  no row locks; uses a version
--     column. Useful for HTTP-style "edit then save" flows where
--     holding a row lock across the network round-trip is wasteful.
-- =====================================================================
ALTER TABLE account ADD COLUMN IF NOT EXISTS version_no INTEGER DEFAULT 1;

-- Session A reads balance + version
BEGIN;
SELECT balance, version_no FROM account WHERE account_number = 'SP0001110001';
--   balance=215000, version_no=1

-- Session B reads the same row (concurrent)
-- BEGIN;
-- SELECT balance, version_no FROM account WHERE account_number = 'SP0001110001';

-- Session A updates, bumping the version
UPDATE account
   SET balance = balance + 1000,
       version_no = version_no + 1
 WHERE account_number = 'SP0001110001'
   AND version_no = 1;     -- conditional update - 1 row affected
COMMIT;

-- Session B tries to update using the stale version it read earlier
-- UPDATE account SET balance = balance + 1000, version_no = version_no + 1
--  WHERE account_number = 'SP0001110001' AND version_no = 1;
--   -> 0 rows affected (the version was bumped by Session A)
-- The application detects "0 rows updated" and asks the user to
-- reload and retry. No lock was held during the user's think time.

-- Cleanup
ALTER TABLE account DROP COLUMN IF EXISTS version_no;

-- =====================================================================
-- End of 02_concurrency.sql
-- =====================================================================
