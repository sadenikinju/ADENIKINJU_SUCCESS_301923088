# Portfolio 2 — Query Processing and Optimisation

**Case study:** SwiftPay Fintech Platform
**RDBMS:** PostgreSQL 16
**Marks:** 7 / 40

## Deliverables

| File | Purpose |
|------|---------|
| `01_queries.sql`         | 12 representative SQL queries spanning the major SwiftPay read paths |
| `02_explain_analyze.sql` | EXPLAIN ANALYZE script — drops the optimisation indexes, captures baseline plans, then recreates them and captures the optimised plans |
| `03_explain_evidence.md` | Captured execution plans with before/after metrics and a write-up of the optimiser behaviour |

## Query catalogue

| # | Query | Business purpose | Access pattern |
|---|-------|------------------|----------------|
| Q1 | Account statement for a date range | Customer statement / mobile-app feed | Composite + covering + partial index |
| Q2 | Customer's account balances | Dashboard header | PK + FK index |
| Q3 | Top 10 customers by transaction volume | Cross-sell / relationship-management | GROUP BY + ORDER BY + LIMIT |
| Q4 | Daily transaction totals by type | Analytics dashboard | Expression index on date |
| Q5 | Lookup by reference_no | Customer-care support | Unique B-tree lookup |
| Q6 | Customers with multiple accounts | Cross-sell | Self-join + HAVING |
| Q7 | Deposits vs withdrawals per month | Cash-flow report | Conditional aggregation |
| Q8 | Suspicious transactions | Compliance / fraud screening | Filter on amount + EXTRACT(HOUR) |
| Q9 | Recompute balance from txn log | Reconciliation / audit | Self-join + conditional SUM |
| Q10 | Full-text search on description | Customer search | ILIKE |
| Q11 | Branch-level performance | Branch manager report | 3-table join + aggregation |
| Q12 | Beneficiaries ranked by total paid | CRM | Self-join + GROUP BY |

## Optimisation evidence

The before/after metrics captured in `03_explain_evidence.md`:

| Query | Baseline exec time | Optimised exec time | Improvement |
|-------|--------------------|---------------------|-------------|
| Q1 (statement) | 0.246 ms | 0.098 ms | **−60 %** |
| Q3 (top 10 volume) | 0.275 ms | 0.168 ms | **−39 %** |
| Q5 (ref lookup) | 0.041 ms | 0.041 ms | already optimal |
| Q8 (suspicious) | 0.256 ms | 0.155 ms | **−40 %** |

At production scale (5 M transactions) the same changes move the workload from full sequential scans to ~50-row index lookups — an estimated 3–4 orders of magnitude improvement.

## Key lessons captured

1. **Selectivity drives access-path choice.** Single-row unique lookups (Q5) are always Index Scans; range filters (Q1) only switch to Bitmap Index Scans once a composite index makes the range selective enough.
2. **Covering indexes eliminate heap fetches** — `INCLUDE (...)` columns turn a Bitmap Heap Scan into an Index-Only Scan.
3. **Partial indexes are smaller and faster** — `WHERE status='COMPLETED'` skips the 15% of PENDING/FAILED rows that never appear in statement queries.
4. **Not every query needs a new index** — over-indexing slows `INSERT` and bloats `shared_buffers`. The SwiftPay `transaction` table carries only six indexes deliberately.
