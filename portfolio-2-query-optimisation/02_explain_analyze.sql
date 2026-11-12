-- =====================================================================
-- MIT 8103 - Portfolio 2: Optimisation evidence
-- File: 02_explain_analyze.sql
-- =====================================================================
-- Run each EXPLAIN ANALYZE statement and compare the plans captured in
-- 03_explain_evidence.md.
--
-- Demonstration methodology:
--   STEP A: DROP the optimisation indexes and capture the baseline plan.
--   STEP B: CREATE the optimisation indexes and capture the improved plan.
--   STEP C: Compare cost, rows, and execution time.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP A - BASELINE (drop optimisation indexes)
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_txn_from_acct_date;
DROP INDEX IF EXISTS idx_txn_to_acct_date;
DROP INDEX IF EXISTS idx_txn_from_covering;
DROP INDEX IF EXISTS idx_txn_to_covering;
DROP INDEX IF EXISTS idx_txn_completed_partial;
DROP INDEX IF EXISTS idx_txn_status_date;
DROP INDEX IF EXISTS idx_txn_from_account;
DROP INDEX IF EXISTS idx_txn_to_account;
ANALYZE transaction;

-- =====================================================================
-- Q1-baseline: Account statement - sequential scan over transactions
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT  t.reference_no, t.initiated_at, t.amount, tt.type_name, t.status
FROM    account      a
JOIN    transaction  t  ON (t.from_account_id = a.account_id
                         OR t.to_account_id   = a.account_id)
JOIN    transaction_type tt ON tt.type_id = t.type_id
WHERE   a.account_number = 'SP0001110001'
  AND   t.initiated_at >= '2026-09-01'
  AND   t.initiated_at <  '2026-10-05'
  AND   t.status = 'COMPLETED'
ORDER BY t.initiated_at DESC;

-- =====================================================================
-- Q3-baseline: Top 10 customers by volume - hash join, full scan
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        COUNT(*) AS transaction_count,
        SUM(t.amount) AS total_volume
FROM    customer    c
JOIN    account     a ON a.customer_id = c.customer_id
JOIN    transaction t ON t.from_account_id = a.account_id
WHERE   t.status = 'COMPLETED'
  AND   t.initiated_at >= '2026-09-01'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_volume DESC
LIMIT 10;

-- =====================================================================
-- Q5-baseline: Lookup by reference_no
-- (idx_txn_reference is intentionally NOT dropped - it is a unique
--  business-key index needed for referential integrity in real use.)
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  t.reference_no, t.initiated_at, t.amount, t.status, t.channel
FROM    transaction t
WHERE   t.reference_no = 'TXN-20260901-001';

-- =====================================================================
-- Q8-baseline: Suspicious transactions - filter on amount + hour
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  t.reference_no, t.initiated_at, t.amount, tt.type_name
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
JOIN    account          fa ON fa.account_id = t.from_account_id
JOIN    customer         c  ON c.customer_id  = fa.customer_id
WHERE   t.status = 'COMPLETED'
  AND  (t.amount > 100000
        OR EXTRACT(HOUR FROM t.initiated_at) NOT BETWEEN 6 AND 21)
ORDER BY t.amount DESC;

-- ---------------------------------------------------------------------
-- STEP B - OPTIMISED (recreate the optimisation indexes)
-- ---------------------------------------------------------------------
-- reuse the Portfolio-1 index script
\ir ../portfolio-1-database-design/02_indexes.sql
ANALYZE transaction;

-- =====================================================================
-- Q1-optimised: same query, now served by the COVERING + PARTIAL index
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  t.reference_no, t.initiated_at, t.amount, tt.type_name, t.status
FROM    account      a
JOIN    transaction  t  ON (t.from_account_id = a.account_id
                         OR t.to_account_id   = a.account_id)
JOIN    transaction_type tt ON tt.type_id = t.type_id
WHERE   a.account_number = 'SP0001110001'
  AND   t.initiated_at >= '2026-09-01'
  AND   t.initiated_at <  '2026-10-05'
  AND   t.status = 'COMPLETED'
ORDER BY t.initiated_at DESC;

-- =====================================================================
-- Q3-optimised: GROUP BY now served by composite index
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        COUNT(*) AS transaction_count,
        SUM(t.amount) AS total_volume
FROM    customer    c
JOIN    account     a ON a.customer_id = c.customer_id
JOIN    transaction t ON t.from_account_id = a.account_id
WHERE   t.status = 'COMPLETED'
  AND   t.initiated_at >= '2026-09-01'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_volume DESC
LIMIT 10;

-- =====================================================================
-- Q5-optimised: Index scan on idx_txn_reference (single-row lookup)
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  t.reference_no, t.initiated_at, t.amount, t.status, t.channel
FROM    transaction t
WHERE   t.reference_no = 'TXN-20260901-001';

-- =====================================================================
-- Q8-optimised: Partial index + bitmap scan on amount
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT  t.reference_no, t.initiated_at, t.amount, tt.type_name
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
JOIN    account          fa ON fa.account_id = t.from_account_id
JOIN    customer         c  ON c.customer_id  = fa.customer_id
WHERE   t.status = 'COMPLETED'
  AND  (t.amount > 100000
        OR EXTRACT(HOUR FROM t.initiated_at) NOT BETWEEN 6 AND 21)
ORDER BY t.amount DESC;

-- =====================================================================
-- Statistics gathering after index rebuild (so the planner trusts them)
-- =====================================================================
ANALYZE account;
ANALYZE transaction;
ANALYZE transaction_log;
ANALYZE customer;

-- =====================================================================
-- End of EXPLAIN ANALYZE script
-- =====================================================================
