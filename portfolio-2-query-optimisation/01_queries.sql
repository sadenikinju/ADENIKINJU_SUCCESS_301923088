-- =====================================================================
-- MIT 8103 - Portfolio 2: Query Processing and Optimisation
-- Case Study: SwiftPay Fintech Platform
-- File: 01_queries.sql
-- Target: PostgreSQL 16
-- =====================================================================
-- Twelve representative queries covering the most common read paths
-- in a digital banking platform. Each query is preceded by a comment
-- block describing its business purpose and expected access pattern.
-- =====================================================================

\set QUIET ON

-- =====================================================================
-- Q1.  Account statement for a customer within a date range
--      (the hottest read path in any banking system)
--      Access path: idx_txn_from_covering / idx_txn_to_covering
-- =====================================================================
SELECT  t.reference_no,
        t.initiated_at,
        CASE
            WHEN t.from_account_id = a.account_id THEN 'DEBIT'
            ELSE 'CREDIT'
        END                          AS direction,
        t.amount,
        tt.type_name                 AS transaction_type,
        t.status,
        t.description
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
-- Q2.  Current account balance for one customer (all their accounts)
-- =====================================================================
SELECT  c.first_name || ' ' || c.last_name  AS customer_name,
        a.account_number,
        a.account_type,
        a.balance,
        a.currency,
        a.status
FROM    customer c
JOIN    account  a ON a.customer_id = c.customer_id
WHERE   c.email = 'chinwe.okoro@example.com'
ORDER BY a.account_type;


-- =====================================================================
-- Q3.  Top 10 customers by total transaction volume (debits sent)
--      Aggregation: GROUP BY customer, SUM(amount), ORDER BY DESC
-- =====================================================================
SELECT  c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        COUNT(*)                             AS transaction_count,
        SUM(t.amount)                        AS total_volume
FROM    customer    c
JOIN    account     a ON a.customer_id = c.customer_id
JOIN    transaction t ON t.from_account_id = a.account_id
WHERE   t.status = 'COMPLETED'
  AND   t.initiated_at >= '2026-09-01'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_volume DESC
LIMIT 10;


-- =====================================================================
-- Q4.  Daily transaction totals by type (for the analytics dashboard)
-- =====================================================================
SELECT  t.initiated_at::date                 AS txn_date,
        tt.type_name,
        COUNT(*)                             AS txn_count,
        SUM(t.amount)                        AS total_amount
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
WHERE   t.status = 'COMPLETED'
  AND   t.initiated_at >= '2026-09-01'
  AND   t.initiated_at <  '2026-10-01'
GROUP BY t.initiated_at::date, tt.type_name
ORDER BY txn_date DESC, total_amount DESC;


-- =====================================================================
-- Q5.  Find a transaction by its reference number (customer-care lookup)
-- =====================================================================
SELECT  t.reference_no,
        t.initiated_at,
        t.amount,
        tt.type_name,
        t.status,
        t.channel,
        t.description,
        fa.account_number  AS from_account,
        ta.account_number  AS to_account
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
LEFT JOIN account fa ON fa.account_id = t.from_account_id
LEFT JOIN account ta ON ta.account_id = t.to_account_id
WHERE   t.reference_no = 'TXN-20260901-001';


-- =====================================================================
-- Q6.  Customers with more than one account (cross-sell opportunity)
-- =====================================================================
SELECT  c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        COUNT(a.account_id)                  AS account_count,
        SUM(a.balance)                       AS total_balance
FROM    customer c
JOIN    account  a ON a.customer_id = c.customer_id
WHERE   a.status = 'ACTIVE'
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING  COUNT(a.account_id) > 1
ORDER BY total_balance DESC;


-- =====================================================================
-- Q7.  Total deposits vs withdrawals per month (cash-flow analysis)
-- =====================================================================
SELECT  TO_CHAR(t.initiated_at, 'YYYY-MM')  AS txn_month,
        SUM(CASE WHEN tt.type_code = 'DEP' THEN t.amount ELSE 0 END)  AS deposits,
        SUM(CASE WHEN tt.type_code = 'WTH' THEN t.amount ELSE 0 END)  AS withdrawals,
        SUM(CASE WHEN tt.type_code = 'TRF' THEN t.amount ELSE 0 END)  AS transfers,
        SUM(CASE WHEN tt.type_code = 'BIL' THEN t.amount ELSE 0 END)  AS bills
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
WHERE   t.status = 'COMPLETED'
GROUP BY TO_CHAR(t.initiated_at, 'YYYY-MM')
ORDER BY txn_month DESC;


-- =====================================================================
-- Q8.  Suspicious transactions: amount > 100,000 OR off-hours (22:00-06:00)
--      Compliance / fraud-screening use case
-- =====================================================================
SELECT  t.reference_no,
        t.initiated_at,
        t.amount,
        tt.type_name,
        c.first_name || ' ' || c.last_name  AS customer_name,
        fa.account_number
FROM    transaction      t
JOIN    transaction_type tt ON tt.type_id = t.type_id
JOIN    account          fa ON fa.account_id = t.from_account_id
JOIN    customer         c  ON c.customer_id  = fa.customer_id
WHERE   t.status = 'COMPLETED'
  AND  (t.amount > 100000
        OR EXTRACT(HOUR FROM t.initiated_at) NOT BETWEEN 6 AND 21)
ORDER BY t.amount DESC, t.initiated_at DESC;


-- =====================================================================
-- Q9.  Recompute account balance from the transaction log
--      (audit / reconciliation query)
-- =====================================================================
SELECT  a.account_number,
        a.balance                                          AS stored_balance,
        COALESCE(SUM(CASE
            WHEN t.to_account_id   = a.account_id THEN  t.amount
            WHEN t.from_account_id = a.account_id THEN -t.amount
            ELSE 0 END), 0)                                AS computed_balance,
        a.balance
        - COALESCE(SUM(CASE
            WHEN t.to_account_id   = a.account_id THEN  t.amount
            WHEN t.from_account_id = a.account_id THEN -t.amount
            ELSE 0 END), 0)                                AS drift
FROM    account      a
LEFT JOIN transaction t ON (t.from_account_id = a.account_id
                          OR t.to_account_id   = a.account_id)
   AND   t.status = 'COMPLETED'
WHERE   a.account_number = 'SP0001110001'
GROUP BY a.account_number, a.balance;


-- =====================================================================
-- Q10. Full-text search across transaction descriptions
-- =====================================================================
SELECT  t.reference_no,
        t.initiated_at,
        t.amount,
        t.description
FROM    transaction t
WHERE   t.description ILIKE '%transfer%'
   OR   t.description ILIKE '%salary%'
ORDER BY t.initiated_at DESC
LIMIT 20;


-- =====================================================================
-- Q11. Branch-level performance: total volume per branch in a month
-- =====================================================================
SELECT  b.branch_name,
        COUNT(t.transaction_id)            AS txn_count,
        SUM(t.amount)                       AS total_volume,
        AVG(t.amount)::numeric(15,2)        AS avg_txn_size
FROM    branch       b
JOIN    account      a  ON a.branch_id = b.branch_id
JOIN    transaction  t  ON t.from_account_id = a.account_id
WHERE   t.status = 'COMPLETED'
  AND   t.initiated_at >= '2026-09-01'
  AND   t.initiated_at <  '2026-10-01'
GROUP BY b.branch_name
ORDER BY total_volume DESC;


-- =====================================================================
-- Q12. Beneficiaries ranked by total amount sent
-- =====================================================================
SELECT  b.beneficiary_name,
        b.nickname,
        COUNT(t.transaction_id) AS times_paid,
        SUM(t.amount)            AS total_paid
FROM    beneficiary b
JOIN    account     fa ON fa.account_id = b.beneficiary_account_id
JOIN    account     ta ON ta.customer_id = b.customer_id
JOIN    transaction t  ON t.from_account_id = ta.account_id
                       AND t.to_account_id = fa.account_id
WHERE   t.status = 'COMPLETED'
GROUP BY b.beneficiary_name, b.nickname
ORDER BY total_paid DESC;

-- =====================================================================
-- End of queries
-- =====================================================================
