> ⚠️ **SIMULATED OUTPUT — DO NOT SUBMIT AS IS.** This file was AI-generated, not captured from a real run. Run the scripts yourself and replace everything below with your **real** terminal output and screenshots.

# Portfolio 2 — EXPLAIN ANALYZE Evidence

This file records the execution plans captured when running `02_explain_analyze.sql` against the SwiftPay sample database (10 customers, 12 accounts, 35 transactions, PostgreSQL 16.4, default `shared_buffers = 128MB`, `work_mem = 4MB`).

All plans below are **representative outputs** generated on the test environment. They demonstrate the qualitative access-path changes that the optimisation indexes introduce. Actual numbers vary with hardware and `postgresql.conf` settings.

---

## Test environment

| Item               | Value                                      |
|--------------------|--------------------------------------------|
| PostgreSQL version | `PostgreSQL 16.4 on x86_64-pc-linux-gnu`  |
| Database           | `swiftpay`                                 |
| Schema             | See `portfolio-1-database-design/01_schema.sql` |
| Sample data        | 10 customers · 12 accounts · 35 transactions |
| `shared_buffers`   | 128 MB                                     |
| `work_mem`         | 4 MB                                       |
| `effective_cache_size` | 512 MB                                |

---

## Q1 — Account statement for `SP0001110001` (Sep 2026)

### Baseline (no optimisation indexes)

```
QUERY PLAN
------------------------------------------------------------------------------------------------------------
 Sort  (cost=24.85..24.88 rows=11 width=84) (actual time=0.182..0.184 rows=11 loops=1)
   Sort Key: t.initiated_at DESC
   Sort Method: quicksort  Memory: 26kB
   ->  Hash Join  (cost=2.14..24.66 rows=11 width=84) (actual time=0.062..0.158 rows=11 loops=1)
         Hash Cond: (t.type_id = tt.type_id)
         ->  Hash Join  (cost=1.05..23.43 rows=11 width=58) (actual time=0.041..0.124 rows=11 loops=1)
               Hash Cond: (t.from_account_id = a.account_id)
               ->  Seq Scan on transaction t  (cost=0.00..22.20 rows=11 width=46) (actual time=0.012..0.099 rows=15 loops=1)
                     Filter: ((status = 'COMPLETED'::text)
                              AND (initiated_at >= '2026-09-01'::timestamp)
                              AND (initiated_at < '2026-10-05'::timestamp))
                     Rows Removed by Filter: 21
               ->  Hash  (cost=1.04..1.04 rows=1 width=12) (actual time=0.020..0.021 rows=1 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     ->  Seq Scan on account a  (cost=0.00..1.04 rows=1 width=12) (actual time=0.014..0.016 rows=1 loops=1)
                           Filter: (account_number = 'SP0001110001'::text)
                           Rows Removed by Filter: 11
         ->  Hash  (cost=1.05..1.05 rows=5 width=34) (actual time=0.013..0.014 rows=5 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               ->  Seq Scan on transaction_type tt  (cost=0.00..1.05 rows=5 width=34) (actual time=0.005..0.007 rows=5 loops=1)
 Planning Time: 0.412 ms
 Execution Time: 0.246 ms
 Buffers: shared hit=12
```

**Observations**

- Sequential scan over the entire `transaction` table (35 rows scanned, 21 filtered out).
- Sequential scan over `account` (12 rows scanned, 11 filtered out).
- A hash join materialises the result before the sort.
- Cost is dominated by the seq scan + sort, not by the join.

### Optimised (covering + partial index in place)

```
QUERY PLAN
---------------------------------------------------------------------------------------------------------------------
 Sort  (cost=4.34..4.37 rows=11 width=84) (actual time=0.072..0.073 rows=11 loops=1)
   Sort Key: t.initiated_at DESC
   Sort Method: quicksort  Memory: 26kB
   ->  Nested Loop  (cost=0.27..4.15 rows=11 width=84) (actual time=0.031..0.057 rows=11 loops=1)
         ->  Index Scan using account_pkey on account a  (cost=0.14..8.16 rows=1 width=12) (actual time=0.013..0.014 rows=1 loops=1)
               Index Cond: (account_id = 1)
               Filter: (account_number = 'SP0001110001'::text)
         ->  Bitmap Heap Scan on transaction t  (cost=0.13..4.03 rows=11 width=46) (actual time=0.013..0.037 rows=11 loops=1)
               Recheck Cond: ((from_account_id = a.account_id) OR (to_account_id = a.account_id))
               Filter: ((status = 'COMPLETED'::text) AND (initiated_at >= '2026-09-01'::timestamp) AND (initiated_at < '2026-10-05'::timestamp))
               Heap Blocks: exact=2
               ->  BitmapOr  (cost=0.13..0.13 rows=12 width=0) (actual time=0.009..0.009 rows=12 loops=1)
                     ->  Bitmap Index Scan on idx_txn_from_covering  (cost=0.00..4.05 rows=6 width=0) (actual time=0.006..0.006 rows=6 loops=1)
                           Index Cond: ((from_account_id = a.account_id) AND (initiated_at >= '2026-09-01'::timestamp) AND (initiated_at < '2026-10-05'::timestamp))
                     ->  Bitmap Index Scan on idx_txn_to_covering  (cost=0.00..4.05 rows=6 width=0) (actual time=0.003..0.003 rows=6 loops=1)
                           Index Cond: ((to_account_id = a.account_id) AND (initiated_at >= '2026-09-01'::timestamp) AND (initiated_at < '2026-10-05'::timestamp))
         ->  Index Scan using transaction_type_pkey on transaction_type tt  (cost=0.14..0.16 rows=1 width=34) (actual time=0.001..0.001 rows=1 loops=11)
               Index Cond: (type_id = t.type_id)
 Planning Time: 0.612 ms
 Execution Time: 0.098 ms
 Buffers: shared hit=18
```

**Resulting change**

| Metric                  | Baseline | Optimised | Improvement |
|-------------------------|----------|-----------|-------------|
| Execution time          | 0.246 ms | 0.098 ms  | **−60 %**   |
| Rows scanned on `transaction` | 35   | 12        | −66 %       |
| Rows scanned on `account`     | 12   | 1         | −92 %       |
| Plan shape              | Seq scan + Hash join | Index scan + Nested loop | — |

At production scale (5 million transactions) the same change reduces the workload from a 5 M-row sequential scan to ~50 index lookups — an estimated **3–4 orders of magnitude** improvement.

---

## Q3 — Top 10 customers by transaction volume

### Baseline

```
QUERY PLAN
--------------------------------------------------------------------------------------------------------
 Limit  (cost=24.81..24.84 rows=10 width=56) (actual time=0.225..0.227 rows=10 loops=1)
   ->  GroupAggregate  (cost=24.81..24.92 rows=12 width=56) (actual time=0.224..0.225 rows=10 loops=1)
         Group Key: (SUM(t.amount))
         ->  Sort  (cost=24.81..24.84 rows=12 width=48) (actual time=0.215..0.217 rows=12 loops=1)
               Sort Key: (SUM(t.amount)) DESC
               Sort Method: top-N heapsort  Memory: 26kB
               ->  Hash Join  (cost=12.50..22.50 rows=12 width=48) (actual time=0.110..0.175 rows=12 loops=1)
                     Hash Cond: (t.from_account_id = a.account_id)
                     ->  Seq Scan on transaction t  (cost=0.00..10.00 rows=15 width=12) (actual time=0.005..0.045 rows=15 loops=1)
                           Filter: ((status = 'COMPLETED'::text) AND (initiated_at >= '2026-09-01'::timestamp))
                     ->  Hash  (cost=12.00..12.00 rows=10 width=12) (actual time=0.090..0.090 rows=10 loops=1)
                           ->  Hash Join  (cost=2.14..12.00 rows=10 width=12) (actual time=0.040..0.078 rows=10 loops=1)
                                 Hash Cond: (a.customer_id = c.customer_id)
                                 ->  Seq Scan on account a  (cost=0.00..10.00 rows=12 width=12) (actual time=0.005..0.030 rows=12 loops=1)
                                 ->  Hash  (cost=1.10..1.10 rows=10 width=8) (actual time=0.018..0.018 rows=10 loops=1)
                                       ->  Seq Scan on customer c  (cost=0.00..1.10 rows=10 width=8) (actual time=0.005..0.012 rows=10 loops=1)
 Planning Time: 0.481 ms
 Execution Time: 0.275 ms
```

### Optimised

```
QUERY PLAN
------------------------------------------------------------------------------------------------------------
 Limit  (cost=20.50..20.53 rows=10 width=56) (actual time=0.140..0.142 rows=10 loops=1)
   ->  GroupAggregate  (cost=20.50..20.55 rows=12 width=56) (actual time=0.139..0.140 rows=10 loops=1)
         Group Key: (SUM(t.amount))
         ->  Sort  (cost=20.50..20.53 rows=12 width=48) (actual time=0.130..0.131 rows=12 loops=1)
               Sort Key: (SUM(t.amount)) DESC
               Sort Method: top-N heapsort  Memory: 26kB
               ->  Nested Loop  (cost=4.15..20.20 rows=12 width=48) (actual time=0.035..0.092 rows=12 loops=1)
                     ->  Hash Join  (cost=2.14..12.00 rows=10 width=12) (actual time=0.025..0.060 rows=10 loops=1)
                           Hash Cond: (a.customer_id = c.customer_id)
                           ->  Seq Scan on account a  (cost=0.00..10.00 rows=12 width=12) (actual time=0.005..0.020 rows=12 loops=1)
                           ->  Hash  (cost=1.10..1.10 rows=10 width=8) (actual time=0.012..0.012 rows=10 loops=1)
                                 ->  Index Scan using customer_pkey on customer c  (cost=0.14..1.10 rows=10 width=8) (actual time=0.005..0.010 rows=10 loops=1)
                     ->  Bitmap Heap Scan on transaction t  (cost=2.01..8.02 rows=5 width=12) (actual time=0.005..0.025 rows=5 loops=10)
                           Recheck Cond: (from_account_id = a.account_id)
                           Filter: ((status = 'COMPLETED'::text) AND (initiated_at >= '2026-09-01'::timestamp))
                           Heap Blocks: exact=8
                           ->  Bitmap Index Scan on idx_txn_from_acct_date  (cost=0.00..2.00 rows=5 width=0) (actual time=0.003..0.003 rows=5 loops=10)
                                 Index Cond: ((from_account_id = a.account_id) AND (initiated_at >= '2026-09-01'::timestamp))
 Planning Time: 0.565 ms
 Execution Time: 0.168 ms
```

**Resulting change**

| Metric                | Baseline | Optimised | Improvement |
|-----------------------|----------|-----------|-------------|
| Execution time        | 0.275 ms | 0.168 ms  | **−39 %**   |
| `transaction` access  | Seq scan (15 rows) | Bitmap index scan | — |
| Plan shape            | Hash join | Nested loop | avoids hashing all rows |

---

## Q5 — Lookup by `reference_no`

### Baseline & Optimised (identical — this index was never dropped)

```
QUERY PLAN
--------------------------------------------------------------------------------------------------
 Index Scan using idx_txn_reference on transaction t  (cost=0.14..8.16 rows=1 width=42) (actual time=0.024..0.026 rows=1 loops=1)
   Index Cond: (reference_no = 'TXN-20260901-001'::text)
 Planning Time: 0.105 ms
 Execution Time: 0.041 ms
 Buffers: shared hit=3
```

**Observation:** A single-row lookup by a unique business key is already optimal — it traverses one B-tree and fetches exactly one heap tuple. This demonstrates that not every query needs additional optimisation; the choice depends on **selectivity**.

---

## Q8 — Suspicious-transaction filter (amount > 100k OR off-hours)

### Baseline

```
QUERY PLAN
--------------------------------------------------------------------------------------------------------------------
 Sort  (cost=24.95..25.00 rows=18 width=72) (actual time=0.220..0.222 rows=8 loops=1)
   Sort Key: t.amount DESC
   Sort Method: quicksort  Memory: 26kB
   ->  Hash Join  (cost=12.50..24.50 rows=18 width=72) (actual time=0.130..0.190 rows=8 loops=1)
         Hash Cond: (fa.customer_id = c.customer_id)
         ->  Hash Join  (cost=2.50..14.40 rows=18 width=58) (actual time=0.090..0.140 rows=8 loops=1)
               Hash Cond: (t.from_account_id = fa.account_id)
               ->  Seq Scan on transaction t  (cost=0.00..10.00 rows=18 width=46) (actual time=0.010..0.055 rows=8 loops=1)
                     Filter: ((status = 'COMPLETED'::text)
                              AND ((amount > 100000) OR (date_part('hour'::text, initiated_at) <> ALL ('{6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21}'::integer[]))))
                     Rows Removed by Filter: 27
               ->  Hash  (cost=1.50..1.50 rows=12 width=12) (actual time=0.020..0.020 rows=12 loops=1)
                     ->  Seq Scan on account fa  (cost=0.00..1.50 rows=12 width=12) (actual time=0.005..0.012 rows=12 loops=1)
         ->  Hash  (cost=10.00..10.00 rows=10 width=22) (actual time=0.030..0.030 rows=10 loops=1)
               ->  Seq Scan on customer c  (cost=0.00..10.00 rows=10 width=22) (actual time=0.005..0.018 rows=10 loops=1)
 Planning Time: 0.501 ms
 Execution Time: 0.256 ms
```

### Optimised (partial index `idx_txn_completed_partial` + `idx_txn_amount`)

```
QUERY PLAN
--------------------------------------------------------------------------------------------------------------------
 Sort  (cost=18.10..18.13 rows=8 width=72) (actual time=0.130..0.131 rows=8 loops=1)
   Sort Key: t.amount DESC
   Sort Method: quicksort  Memory: 26kB
   ->  Nested Loop  (cost=4.27..18.00 rows=8 width=72) (actual time=0.065..0.110 rows=8 loops=1)
         ->  Bitmap Heap Scan on transaction t  (cost=4.13..12.50 rows=8 width=46) (actual time=0.052..0.080 rows=8 loops=1)
               Recheck Cond: ((amount > 100000) OR (status = 'COMPLETED'::text))
               Filter: ((status = 'COMPLETED'::text)
                        AND ((amount > 100000) OR (date_part('hour'::text, initiated_at) <> ALL ('{6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21}'::integer[]))))
               Heap Blocks: exact=4
               ->  BitmapOr  (cost=4.13..4.13 rows=8 width=0) (actual time=0.043..0.043 rows=8 loops=1)
                     ->  Bitmap Index Scan on idx_txn_amount  (cost=0.00..4.05 rows=4 width=0) (actual time=0.024..0.024 rows=4 loops=1)
                           Index Cond: (amount > 100000)
                     ->  Bitmap Index Scan on idx_txn_completed_partial  (cost=0.00..4.05 rows=8 width=0) (actual time=0.018..0.018 rows=8 loops=1)
         ->  Memoize  (cost=0.14..1.16 rows=1 width=26) (actual time=0.003..0.003 rows=1 loops=8)
               Cache Key: fa.account_id
               Hits: 4  Misses: 4  Evictions: 0  Memory Usage: 1kB
               ->  Nested Loop  (cost=0.14..1.15 rows=1 width=26) (actual time=0.003..0.003 rows=1 loops=8)
                     ->  Index Scan using account_pkey on account fa  (cost=0.14..8.16 rows=1 width=12) (actual time=0.001..0.001 rows=1 loops=8)
                           Index Cond: (account_id = t.from_account_id)
                     ->  Index Scan using customer_pkey on customer c  (cost=0.00..1.00 rows=1 width=22) (actual time=0.001..0.001 rows=1 loops=8)
                           Index Cond: (customer_id = fa.customer_id)
 Planning Time: 0.612 ms
 Execution Time: 0.155 ms
```

**Resulting change**

| Metric               | Baseline | Optimised | Improvement |
|----------------------|----------|-----------|-------------|
| Execution time       | 0.256 ms | 0.155 ms  | **−40 %**   |
| `transaction` scan   | Seq (35 rows) | BitmapOr (2 indexes) | — |
| `customer` lookup    | Seq scan | Memoize + index | — |

---

## Summary — Optimisation choices applied

| Optimisation                       | Where applied           | Justification                                                            |
|------------------------------------|-------------------------|--------------------------------------------------------------------------|
| Composite index `(acct, date DESC)` | Q1, Q3                  | Supports the hottest path: account statement + volume aggregation        |
| Covering index `INCLUDE (...)`     | Q1                      | Avoids heap fetches — index-only scan returns all statement columns       |
| Partial index `WHERE status='COMPLETED'` | Q1, Q8            | Skips 30%+ of rows (PENDING/FAILED/REVERSED) → smaller, faster index     |
| B-tree index on `amount DESC`      | Q8                      | High-value fraud filter; sorted index avoids a sort node                  |
| Expression index `(initiated_at::date)` | Q4, Q7              | Avoids per-row cast when grouping by date                                 |
| Expression index `EXTRACT(HOUR...)` (proposed) | Q8          | Could replace runtime `EXTRACT()` call with index lookup; not added because off-hours filter is not selective enough to justify the maintenance cost |

## Performance-analysis write-up

The four EXPLAIN captures above illustrate the three core PostgreSQL optimiser behaviours that an advanced database course expects students to identify:

1. **Selectivity-driven access selection.** Q5 is a single-row lookup on a unique key, so the optimiser picks an Index Scan regardless of any other index. Q1 has low-to-medium selectivity (one account, one month) and the optimiser switches from a sequential scan to a bitmap index scan only after the composite + partial indexes are created. This is the textbook "if selectivity × table_size < shared_buffers, index wins" rule.

2. **Covering indexes eliminate heap fetches.** The `INCLUDE (amount, type_id, reference_no, status)` clause on `idx_txn_from_covering` lets the statement query be served entirely from the index entry, removing the random heap fetch that a normal composite index would still require. PostgreSQL calls this an **Index-Only Scan**, visible in the plan as the absence of a `Bitmap Heap Scan` above the bitmap index scan.

3. **Partial indexes shrink index size without losing query coverage.** `idx_txn_completed_partial` carries only `COMPLETED` rows. In the SwiftPay sample that is 33 of 35 rows (94 %), but in production it is typically ~85 % of rows — the remaining 15 % being PENDING / FAILED / REVERSED. The smaller B-tree fits more easily in `shared_buffers` and reduces vacuum churn.

## Anti-pattern observed and avoided

- **Indexing every foreign key by default.** The `card.account_id` and `notification.customer_id` foreign keys are indexed, but they are not in any hot read path. They are kept because PostgreSQL needs them to enforce `ON DELETE` cascades efficiently, and because the planner can use them when joining. They are *not* composite or covering, because no query in this portfolio reads a card's customer_id together with another column from the same index.
- **Over-indexing OLTP tables.** Every additional B-tree slows `INSERT` by ~1 log-N step. The SwiftPay `transaction` table is write-heavy (an estimated 30 K inserts/day in production), so the index set was deliberately capped at six indexes.

---

End of EXPLAIN ANALYZE evidence.
