# Portfolio 3 — Transactions and Concurrency

**Case study:** SwiftPay Fintech Platform
**RDBMS:** PostgreSQL 16
**Marks:** 7 / 40

## Deliverables

| File | Purpose |
|------|---------|
| `01_transactions.sql` | ACID transaction control: BEGIN/COMMIT/ROLLBACK, SAVEPOINT, conditional exception handling, `sp_transfer_funds` stored procedure |
| `02_concurrency.sql`  | Four ANSI isolation levels, lost-update demo, deadlock demo, optimistic concurrency control |
| `03_evidence.md`      | Simulated psql terminal output for every demo (two-session interleavings) |

## Demonstrations

| # | Topic | What it shows |
|---|-------|---------------|
| T1 | Atomic intra-bank transfer | Debit + credit + txn row + audit row, all in one BEGIN/COMMIT |
| T2 | Failed transfer + auto-rollback | CHECK constraint fires; transaction is automatically aborted |
| T3 | SAVEPOINT partial rollback | A multi-step batch where one step fails but the rest survive |
| T4 | Stored procedure `sp_transfer_funds` | Atomic transfer with locking, business rules, audit trail |
| C1 | READ UNCOMMITTED | PostgreSQL maps this to READ COMMITTED — dirty reads are impossible |
| C2 | READ COMMITTED | Permits non-repeatable read |
| C3 | REPEATABLE READ | Prevents non-repeatable read; in PostgreSQL also prevents phantom reads (snapshot isolation) |
| C4 | SERIALIZABLE | Detects write-skew at COMMIT time, aborts one transaction |
| C5 | Lost update (naive vs `FOR UPDATE`) | Two tellers incrementing the same balance; one update is lost without row locks |
| C6 | Deadlock | Two transfers in opposite directions; PostgreSQL detects the cycle in ~1 s |
| C7 | Optimistic concurrency control | Version-column conditional UPDATE — no held locks during user think time |

## Concurrency-control summary for SwiftPay

| Operation | Isolation level | Why |
|-----------|-----------------|-----|
| Fund transfer (debit + credit) | READ COMMITTED + `SELECT … FOR UPDATE` in deterministic account-id order | Avoids lost updates and deadlocks; the default isolation is sufficient because row locks serialise the conflicting writes |
| Balance recomputation / reconciliation | REPEATABLE READ | Needs a stable snapshot so the SUM does not see partial in-flight transfers |
| Compliance screening across many accounts | SERIALIZABLE | Catches write-skew between two compliance agents screening the same customer |
| Bill-payment edit-then-save web flow | READ COMMITTED + OCC (version column) | User think-time is unpredictable; holding a row lock across HTTP round-trips is wasteful |

## Key lessons captured

1. **Lock accounts in deterministic order** — always acquire row locks in ascending `account_id` order. This breaks every potential deadlock cycle.
2. **Use SAVEPOINTs for batch resilience** — a single bad row should not abort an entire batch import.
3. **SERIALIZABLE has a price** — the abort rate is ~0.1–1% under contention; the application must be ready to retry. Use only where the anomaly is unacceptable.
4. **OCC vs PCC** — pessimistic concurrency control (row locks) wins for short, contended critical sections; optimistic (version column) wins for long, uncontended user-think flows.
