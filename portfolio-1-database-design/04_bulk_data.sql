-- =====================================================================
-- MIT 8103 - Portfolio 1 (supports Portfolio 2)
-- File: 04_bulk_data.sql  (volume data so the optimiser behaves realistically)
-- Run AFTER 03_seed_data.sql:  psql -d swiftpay -f 04_bulk_data.sql
--
-- With only 36 rows PostgreSQL always chooses a Seq Scan, because reading a
-- whole tiny table is cheaper than using an index. Adds 5,000 customers,
-- 5,000 accounts and 300,000 completed transfers (Sep-Oct 2026) so that the
-- EXPLAIN ANALYZE before/after comparison in Portfolio 2 is meaningful.
-- setseed() makes the "random" data identical on every run.
-- =====================================================================
BEGIN;
SELECT setseed(0.8103);

INSERT INTO customer (first_name, last_name, email, phone, date_of_birth, gender,
                      national_id, address, city, kyc_status)
SELECT (ARRAY['Ada','Bola','Chidi','Dayo','Efe','Femi','Gbenga','Halima','Ife','Jide'])[1 + (g % 10)],
       (ARRAY['Okafor','Bello','Adeyemi','Eze','Musa','Ojo','Nwankwo','Ibrahim'])[1 + (g % 8)],
       'bulk' || g || '@example.com',
       '+234-80' || LPAD(g::text, 8, '0'),
       DATE '1970-01-01' + (g % 12000),
       (ARRAY['M','F'])[1 + (g % 2)],
       'NG-NIN-B' || LPAD(g::text, 7, '0'),
       g || ' Bulk Street',
       (ARRAY['Lagos','Abuja','Port Harcourt'])[1 + (g % 3)],
       'VERIFIED'
FROM generate_series(1, 5000) g;

INSERT INTO account (account_number, customer_id, branch_id, account_type, balance, status, opened_at)
SELECT 'SPB' || LPAD(g::text, 9, '0'),
       c.customer_id,
       1 + (g % 3),
       'SAVINGS',
       5000000.00,
       'ACTIVE',
       TIMESTAMPTZ '2024-01-01' + (g || ' hours')::interval
FROM generate_series(1, 5000) g
JOIN customer c ON c.email = 'bulk' || g || '@example.com';

-- 300,000 transfers between bulk accounts only (the 12 demo accounts stay readable)
WITH ids AS (SELECT MIN(account_id) AS lo, MAX(account_id) AS hi
               FROM account WHERE account_number LIKE 'SPB%'),
gen AS (
  SELECT g,
         lo + floor(random() * (hi - lo + 1))::bigint                         AS a1,
         lo + floor(random() * (hi - lo + 1))::bigint                         AS a2,
         round((500 + random() * 49500)::numeric, 2)                          AS amt,
         TIMESTAMPTZ '2026-09-01 00:00+01' + random() * INTERVAL '61 days'    AS ts,
         random()                                                             AS r
  FROM generate_series(1, 300000) g, ids
)
INSERT INTO transaction (reference_no, from_account_id, to_account_id, amount, type_id,
                         status, channel, description, initiated_at, completed_at)
SELECT 'BLK-' || LPAD(g::text, 8, '0'),
       a1,
       CASE WHEN a2 = a1 THEN a1 + CASE WHEN a1 = (SELECT hi FROM ids) THEN -1 ELSE 1 END ELSE a2 END,
       amt, 1,
       CASE WHEN r < 0.95 THEN 'COMPLETED' ELSE 'FAILED' END,
       (ARRAY['WEB','MOBILE','API','POS'])[1 + (g % 4)],
       'Bulk transfer',
       ts,
       CASE WHEN r < 0.95 THEN ts + INTERVAL '2 seconds' END
FROM gen;

-- Keep balances consistent with the ledger (same rule as 03_seed_data.sql)
UPDATE account SET opening_balance = balance WHERE account_number LIKE 'SPB%';
UPDATE account a
   SET balance = a.opening_balance
               + COALESCE(c.amt, 0) - COALESCE(d.amt, 0)
  FROM account x
  LEFT JOIN (SELECT to_account_id   AS id, SUM(amount) amt FROM transaction
              WHERE status IN ('COMPLETED','REVERSED') GROUP BY 1) c ON c.id = x.account_id
  LEFT JOIN (SELECT from_account_id AS id, SUM(amount) amt FROM transaction
              WHERE status IN ('COMPLETED','REVERSED') GROUP BY 1) d ON d.id = x.account_id
 WHERE a.account_id = x.account_id
   AND a.account_number LIKE 'SPB%';

COMMIT;
ANALYZE;

SELECT 'customers' AS tbl, COUNT(*) FROM customer
UNION ALL SELECT 'accounts', COUNT(*) FROM account
UNION ALL SELECT 'transactions', COUNT(*) FROM transaction;
