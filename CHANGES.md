# CHANGES — AI-assisted debugging (Claude, Nov 2026)

Every script was run from scratch on PostgreSQL 16 and MongoDB 8. These changes make the scripts run without unexpected errors. The intentional demo errors in Portfolio 3 (T2 overdraft, T3 foreign key) are left as they are.

| # | File | Problem found when run | Fix |
|---|------|------------------------|-----|
| 1 | `portfolio-1-database-design/01_schema.sql` | Seed reversal uses channel `'SYSTEM'`, which is not in the channel CHECK list. The seed file runs inside one BEGIN/COMMIT, so the **whole seed rolled back and the database stayed empty (0 rows)**. | Added `'SYSTEM'` to the `transaction.channel` CHECK. |
| 2 | `portfolio-1-database-design/03_seed_data.sql` | All 5 `card_number_hash` values are 65 characters, but the column is `VARCHAR(64)`, so the card inserts failed. | Trimmed each hash to 64 characters. |
| 3 | `portfolio-1-database-design/02_indexes.sql` | `(initiated_at::date)` on a TIMESTAMPTZ fails: *functions in index expression must be marked IMMUTABLE*. | Changed it to `((initiated_at AT TIME ZONE 'Africa/Lagos')::date)`. Queries must use the same expression to use this index. |
| 4 | `portfolio-3-transactions-concurrency/01_transactions.sql` (T3) | `BEGIN … EXCEPTION … END` in plain SQL is a syntax error, because EXCEPTION blocks only exist inside PL/pgSQL. The INSERT also hit `chk_completed_ts` before the foreign key. | Removed the pseudo try/catch and added `completed_at`, so the INSERT now fails on the **foreign key** as the demo intends. ROLLBACK TO SAVEPOINT then keeps the notification. |
| 5 | same file (T4) | The procedure would not compile: *OUT parameters cannot appear after one with a default value*. | Changed the parameter to `INOUT p_reference VARCHAR DEFAULT NULL`. |
| 6 | same file (T4) | The procedure sets `account.updated_at`, which does not exist. | Removed `updated_at = NOW()` from both UPDATEs. |
| 7 | same file (T4) | The generated reference is 24 characters, but `reference_no` is `VARCHAR(20)`. | The format is now `TXN-YYMMDDHHMISS####`, which is exactly 20 characters. |
| 8 | same file (T4) | The comment says locks are taken in ascending `account_id` order, but the code locked "from" then "to", so A→B and B→A transfers could deadlock. | Added `PERFORM … ORDER BY account_id FOR UPDATE` to lock both rows in id order first. |
| 9 | `portfolio-5-distributed-cloud/01_distributed_setup.sql` | `reference_no UNIQUE` on a partitioned table fails, because a unique key must include the partition key, so the whole partitioning block rolled back. | Changed to `UNIQUE (reference_no, initiated_at)`, with an explanatory comment. |
| 10 | same file | `DROP TABLE transaction_old` failed, because `transaction_log` still has a foreign key to it. The new FK to the partitioned table is also impossible, because `transaction_id` alone is not unique. | Used `DROP … CASCADE` and commented out the FK, with an explanation of the partitioning trade-off. |

**Verified result after the fixes:** 36 transactions and 5 cards load. `sp_transfer_funds` completes a ₦7,500 transfer and writes audit rows. `transaction` is split into the 2026_09, 2026_10 and 2026_11 partitions. Both MongoDB scripts run.

**Not changed (the student must do these):** see the review notes. Real EXPLAIN output and real terminal evidence must replace the simulated files. The documentation must be cut to 2–3 pages. The AI-use declaration must match what actually happened.

## Round 2: design fixes

| # | File | Problem | Fix |
|---|------|---------|-----|
| 11 | `01_schema.sql`, `03_seed_data.sql` | The seed "reversed" a **FAILED** transfer. No money had moved, so the reversal credited ₦9,000 from nowhere. | TXN-…-033 is now a completed transfer that is later reversed (status `REVERSED`), and 033R moves the same ₦9,000 back from account 8 to account 1. New trigger `trg_reversal_valid` rejects reversals of non-completed transactions, a different amount, or the wrong direction. *(Tested: reversing a FAILED txn → ERROR.)* |
| 12 | `01_schema.sql`, `03_seed_data.sql` | Account balances were typed in and did not match the transactions. | Added `account.opening_balance`. The seed now sets `balance = opening_balance + completed credits − debits` and ends with an integrity query that returns **0 rows**. |
| 13 | `01_schema.sql`, `03_seed_data.sql` | `card.cvv_hash` stored the CVV, which PCI DSS forbids even when hashed. | Removed the column and its seed values. |
| 14 | `01_schema.sql` | `CHECK (expiry_date > CURRENT_DATE)` becomes false as cards age, so a pg_dump restore would fail. | Replaced with trigger `trg_card_expiry`, which checks only on issue or update. *(Tested: expiry 2020-01-01 → ERROR.)* |
| 15 | `04_bulk_data.sql` (new) | With 36 rows PostgreSQL always does a Seq Scan, so no index could ever show a benefit. | Generates 5,000 customers and accounts plus 300,000 transfers (reproducible with `setseed`), with balances kept consistent. Loads in about 10 s. |
| 16 | `02_explain_analyze.sql` | `\i 02_indexes.sql` pointed at a file that doesn't exist in that folder. The "baseline" also kept the FK indexes, so it wasn't a real baseline. | Changed to `\ir ../portfolio-1-database-design/02_indexes.sql`, the baseline now also drops the two FK indexes, and `ANALYZE` runs after each step. |
| 17 | `03_explain_evidence.md`, `03_evidence.md` | AI-simulated output presented as evidence. | Added a clear **SIMULATED — replace before submitting** banner. The owner must paste real output. |
| 18 | READMEs | Out of date. | Mention the new file, the triggers and the 36 transactions; removed the CVV. |

**Verified on the 300k-row data (my test run, for reference only):** Q1 account statement went from **Seq Scan, 42.5 ms** to **Bitmap Index Scan on `idx_txn_from/to_covering`, 0.16 ms**. Q5 reference lookup uses `idx_txn_reference` at 0.04 ms. The aggregate reports (Q3, Q4) still use Seq Scan, which is correct when most rows are read, and is worth explaining in the write-up. Partitioning splits the 300,038 rows into 2026_09, 2026_10 and 2026_11.

## Round 3: one-click run in Codespaces (tested end to end, about 45 s)

| # | File | Problem | Fix |
|---|------|---------|-----|
| 19 | `setup.sh`, `runall.sh`, `collect_results.sh` (new) | The project had no runner: every step was a manual `psql` command, so most results were never produced. | `setup.sh` installs PostgreSQL 16 and MongoDB, creates the `swiftpay` database and your database role. `runall.sh` runs P1 to P5 in order, saves `pN_output.log`, commits and pushes each, and starts PostgreSQL/MongoDB again if the Codespace slept. `collect_results.sh` writes `my_results.txt` from real output. |
| 20 | `portfolio-3-transactions-concurrency/race_demos.py` (new) | `02_concurrency.sql` needs two terminals and the evidence file was simulated. | Two real database sessions race a ₦8,000 withdrawal from a ₦10,000 account: the lost-update bug, `FOR UPDATE`, SERIALIZABLE (40001), READ COMMITTED vs REPEATABLE READ, and a deadlock (40P01) with the ordered-lock fix. Output goes to `race_demos_output.log`. |
| 21 | `portfolio-4-nosql/03_bulk_and_index_demo.js` (new) | Only a handful of MongoDB documents, so an index could never matter and there was no explain output. | Loads 40,000 transactions, then compares COLLSCAN with IXSCAN using `explain("executionStats")`. |
| 22 | `portfolio-5-distributed-cloud/02_replica_setup.sh`, `03_replica_tests.sql` (new) | Replication was described but never run. | Builds a streaming replica on port 5433 with `pg_basebackup`, shows the replica refuses a write, and a row written on the primary appears on the replica. |

Real output from the run replaces the simulated evidence files (`03_explain_evidence.md`, `03_evidence.md`) when you add your own screenshots.
