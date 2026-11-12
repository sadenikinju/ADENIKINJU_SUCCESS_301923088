# Portfolio 4 — NoSQL and Advanced Data Models

**Case study:** SwiftPay Fintech Platform
**NoSQL engine:** MongoDB 7.0 (document model)
**Marks:** 7 / 40

## Deliverables

| File | Purpose |
|------|---------|
| `01_mongodb_setup.js`              | Collection creation + `$jsonSchema` validators (mirrors the SQL CHECK constraints) |
| `02_mongodb_data_and_queries.js`   | Seed data + indexes + 6 aggregation-query demonstrations |
| `03_suitability_analysis.md`       | Mapping of relational → document model, modelling decisions, when MongoDB fits vs when it does not |

## Document-model summary

The relational schema's 9 tables map to 5 MongoDB collections:

| Collection | Documents contain | Modelling pattern |
|------------|-------------------|-------------------|
| `customers` | Profile + **embedded** KYC + **embedded** address | Top-level entity with embedded 1:1 sub-documents |
| `accounts` | Account + **embedded** branch snapshot | Denormalised reference data (read-only) |
| `transactions` | Transaction + **embedded** from/to account snapshots + **embedded** audit events array | Snapshot pattern + embedded 1:few array |
| `beneficiaries` | Saved payee (references both customer and account) | Separate collection — independently editable |
| `audit_logs` | Time-series copy of audit events | Parallel collection for cross-transaction compliance queries |

## Key modelling decisions

1. **Embed KYC** inside the customer — a KYC record has no independent life; embedding avoids a join on the hottest customer read.
2. **Snapshot the from/to accounts** inside each transaction — guarantees historical transactions remain readable even after the account is later closed or renamed.
3. **Embed audit events** as an array inside the transaction — always read together with the transaction (single-document fetch).
4. **Hybrid enum + reference collection** for transaction types — the enum string makes reads self-describing; the small reference collection supports the admin UI.

## Suitability verdict

MongoDB is **not** a replacement for PostgreSQL at SwiftPay. The relational database remains the system of record because:
- Multi-step ACID transfers and balance constraints are first-class in PostgreSQL.
- Normalisation protects against the data-integrity risks that are fatal in banking.

MongoDB **is** the right tool for two adjacent workloads:
- The operational read path (denormalised customer profile & statement fetched in a single document read).
- Schema-flexible transaction metadata (different payment channels store different fields without nullable-column bloat).

A production deployment would run **both** — PostgreSQL as authoritative, MongoDB as a derived read model kept in sync via Debezium CDC → Kafka → MongoDB Sink. This is the standard CQRS-with-polyglot-persistence pattern used by Monzo, Nubank, and Stripe.

## How to run

```bash
mongosh swiftpay portfolio-4-nosql/01_mongodb_setup.js
mongosh swiftpay portfolio-4-nosql/02_mongodb_data_and_queries.js
```

Both scripts are idempotent (they drop and recreate the collections on each run).
