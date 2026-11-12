# Portfolio 1 — Database Design and Modelling

**Case study:** SwiftPay Fintech Platform
**RDBMS:** PostgreSQL 16
**Marks:** 7 / 40

## Deliverables

| File | Purpose |
|------|---------|
| `01_schema.sql`   | DDL — 9 tables, primary & foreign keys, CHECK constraints, UNIQUE constraints |
| `02_indexes.sql`  | 10 secondary indexes: composite, covering, partial, expression |
| `03_seed_data.sql`| Realistic Nigerian-bank sample data: 3 branches, 10 customers, 12 accounts, 35 transactions, audit logs, beneficiaries, cards, notifications |
| `04_bulk_data.sql`| 5,000 customers/accounts + 300,000 transfers so EXPLAIN plans in Portfolio 2 are realistic |
| `er_diagram.png`  | Entity-Relationship diagram, 1400×980 px, 9 entities + 11 relationships |

## Case-study description

SwiftPay is a digital banking / fintech platform providing retail banking services to Nigerian customers. The system stores customer profiles (with KYC data), accounts (savings, current, fixed), and transactions (transfers, deposits, withdrawals, bills, reversals). Every transaction is recorded in an append-only audit log; customers may save beneficiaries (payees) for repeat transfers, hold one or more cards, and receive notifications on every debit or credit.

The ER diagram identifies **9 entities** and **11 1:N relationships** (plus one self-reference for reversals). The schema enforces banking-domain integrity rules via CHECK constraints — for example, a SAVINGS account's balance cannot go below zero, while a CURRENT account may overdraw up to NGN 100,000.

## Relational schema (summary)

```
branch(branch_id PK, branch_name, branch_code U, address, city, region, phone, created_at)
customer(customer_id PK, first_name, last_name, email U, phone U, date_of_birth, gender,
         national_id U, address, city, country, kyc_status, created_at, updated_at)
account(account_id PK, account_number U, customer_id FK→customer, branch_id FK→branch,
        account_type, balance, currency, status, opened_at, closed_at)
transaction_type(type_id PK, type_name, type_code U, description)
transaction(transaction_id PK, reference_no U, from_account_id FK→account,
             to_account_id FK→account, amount, currency, type_id FK→transaction_type,
             status, channel, description, initiated_at, completed_at, reversal_of FK→transaction)
transaction_log(log_id PK, transaction_id FK→transaction, event_type, event_data JSONB,
                actor, occurred_at)
beneficiary(beneficiary_id PK, customer_id FK→customer,
            beneficiary_account_id FK→account, beneficiary_name, bank_code, nickname, added_at)
card(card_id PK, card_number_hash U, customer_id FK→customer, account_id FK→account,
     card_type, expiry_date, status, issued_at)
notification(notification_id PK, customer_id FK→customer, message, channel, status,
             created_at, sent_at)
```

`PK` = primary key, `U` = UNIQUE constraint, `FK→` = foreign key.

## Keys, constraints & normalisation

### Keys

- Every table has a **single-column surrogate primary key** (`BIGSERIAL` / `SMALLSERIAL`), guaranteeing a stable identifier even if business keys change.
- Every business key (`account_number`, `reference_no`, `email`, `phone`, `national_id`, `branch_code`, `type_code`, `card_number_hash`) is enforced as `UNIQUE NOT NULL`.
- Foreign keys are explicit on every relationship. `ON DELETE CASCADE` is used only on `transaction_log → transaction` (an audit row has no meaning without its transaction); other FKs default to `RESTRICT` to prevent accidental parent deletion.

### CHECK constraints (domain integrity)

| Constraint | Table | Rule |
|------------|-------|------|
| `chk_balance_limit` | `account` | SAVINGS/FIXED ≥ 0; CURRENT ≥ −100 000 |
| `chk_closed_consistency` | `account` | status='CLOSED' requires closed_at NOT NULL |
| `chk_at_least_one_account` | `transaction` | at least one of from/to account must be non-null |
| `chk_accounts_different` | `transaction` | from_account ≠ to_account |
| `chk_completed_ts` | `transaction` | status='COMPLETED' requires completed_at NOT NULL |
| `chk_customer_dob` | `customer` | date_of_birth must be at least 16 years ago |
| `trg_card_expiry` (trigger) | `card` | expiry_date must be in the future when a card is issued/changed |
| `trg_reversal_valid` (trigger) | `transaction` | only COMPLETED transactions can be reversed, same amount, opposite direction |
| enum-style CHECK | several | gender, kyc_status, account_type, status, event_type, channel |

### Normalisation (3NF / BCNF)

The schema satisfies:

- **1NF** — every column is atomic. Customer name is split into `first_name` and `last_name`; address is a single string but stored once (we accept the trade-off vs splitting into street/city/state for query simplicity — and `city` is already a separate column for indexing).
- **2NF** — no partial-key dependencies. Every table uses a single-column surrogate primary key, so partial-key dependencies are impossible by construction.
- **3NF** — no transitive dependencies. Branch attributes (`branch_name`, `address`, `city`) live in `branch`, not duplicated in `account` — `account` only carries `branch_id`. Transaction-type names live in `transaction_type`, not duplicated in `transaction` — `transaction` only carries `type_id`.
- **BCNF** — every determinant is a candidate key. The only non-trivial determinant chains (`email → customer_id`, `national_id → customer_id`, `account_number → account_id`, `reference_no → transaction_id`) all point at primary keys, so BCNF is preserved.

## Index design

The 10 indexes in `02_indexes.sql` are explained in detail in `portfolio-2-query-optimisation/03_explain_evidence.md`. They are:

1. **Foreign-key support indexes** — PostgreSQL does not auto-index FKs.
2. **Composite index `(account_id, initiated_at DESC)`** — supports the hottest read path: the account statement.
3. **Covering index `INCLUDE (amount, type_id, reference_no, status)`** — enables Index-Only Scans for the statement.
4. **Partial index `WHERE status='COMPLETED'`** — skips PENDING/FAILED/REVERSED rows (~15% smaller).
5. **Expression index `(initiated_at::date)`** — for date-bucketed aggregation queries.
6. **B-tree on `amount DESC`** — for the high-value fraud-screening query.

The index set is deliberately capped at six on the `transaction` table because every additional B-tree slows `INSERT` by ~1 log-N step, and `transaction` is the most write-heavy table (~30 K inserts/day in production).
