# Portfolio 4 — NoSQL Document Model: Suitability Analysis

## 1. Mapping relational entities to MongoDB documents

The SwiftPay relational schema from Portfolio 1 has nine tables. The MongoDB model collapses them into five collections by exploiting the fact that some 1:few relationships are *always read together* and never queried independently.

| Relational table           | MongoDB collection | Modelling decision                                                    |
|----------------------------|--------------------|-----------------------------------------------------------------------|
| `customer`                 | `customers`        | Top-level collection. KYC and address are **embedded** sub-documents. |
| `account`                  | `accounts`         | Top-level collection. Branch info is **embedded** (denormalised snapshot). References `customer_id`. |
| `transaction`              | `transactions`     | Top-level collection. From/to accounts are **embedded snapshots** (denormalised). Audit events are **embedded array**. |
| `transaction_log`          | `transactions.audit_events[]` (embedded) AND `audit_logs` (time-series) | Audit trail lives *inside* the transaction document for fast reads. For very high-volume deployments, a separate time-series collection mirrors the events for long-term analytics. |
| `transaction_type`         | `transaction_types` (small reference collection) **and/or enum string** in each transaction | Hybrid: stored as enum string in transactions (read path), kept as a collection for admin UI (write path). |
| `beneficiary`              | `beneficiaries`    | Separate collection (a beneficiary is independently editable and shares no lifecycle with the transaction). |
| `card`                     | `customers.cards[]` (embedded array) in a real deployment | Out of scope for this portfolio — cards are 1:few per customer, embed them. |
| `notification`             | `notifications` (separate collection) or pushed to a time-series collection | Notifications are write-heavy and queried by date — separate collection is appropriate. |
| `branch`                   | **embedded inside** `accounts.branch` | Read-only reference data; no need for an independent collection. |

## 2. Why these modelling decisions were made

### 2.1 Embedding KYC inside the customer document

A KYC record has no business meaning outside its customer. It is created when the customer is created, updated only when the customer's status changes, and is *always read together* with the customer record (every customer-care screen shows KYC status next to the name). Embedding it eliminates one join per read. The trade-off is that if a regulator demanded KYC to be queried independently (e.g. "show me all KYC verified by user X in the last week"), we would need a separate collection or a secondary index on the embedded field `kyc.verified_by` — both straightforward in MongoDB.

### 2.2 Embedding branch info inside the account

Branch data is effectively static (a branch's name and code do not change day-to-day) and is always shown alongside the account number. Embedding it as a snapshot removes the need to maintain a `branch` collection that would otherwise be a join target for every account read. If a branch *does* rename, the application simply runs a `bulkWrite` to update the embedded fields across all accounts — typically a few thousand documents, completed in under a second.

### 2.3 Embedding from/to account snapshots inside transactions

This is the most consequential decision. In the relational model, a transaction references `from_account_id` and `to_account_id` and joins to `account` whenever account details are needed. In MongoDB, we **snapshot** the account number and customer name at transaction time and embed them.

**Why:** historical transactions must remain readable even after the underlying account is closed or the customer renames. The snapshot pattern guarantees this. Reading a transaction statement is then a single index scan on `from_account.account_no` with no join.

**Trade-off:** if the account's current number is needed (e.g. a "show me all transactions for account X" query that should follow renames), the embedded snapshot is wrong. We accept this trade-off because account numbers are immutable in SwiftPay's business rules.

### 2.4 Embedding audit events inside the transaction

The audit trail for a single transaction is small (typically 3–7 events) and is **always read together** with the transaction itself (the customer-care screen shows the timeline next to the transaction). Embedding the array makes the read a single document fetch.

For very high audit volume (millions of transactions per day), MongoDB 5+ offers time-series collections. We provision a parallel `audit_logs` time-series collection for compliance queries that span many transactions ("show me all FAILED events in the last 24h"). This is a deliberate **CQRS-style** split: the embedded array for the single-transaction read path, the time-series collection for the cross-transaction analytics path.

### 2.5 Hybrid reference + enum for transaction types

Transaction types are a tiny static enumeration. Storing them as a string enum inside each transaction (`type: "TRF"`) makes reads self-describing and removes one join. The small `transaction_types` collection still exists for the admin UI that lets operations staff edit the human-readable name — but the read path never touches it.

## 3. When MongoDB is the right choice for SwiftPay

| Use case                                                         | MongoDB fit           | Why |
|------------------------------------------------------------------|-----------------------|-----|
| Storing transactions with rich, varying metadata (different fields per channel: ATM has terminal_id, BRANCH has teller_id, API has client_id) | **Excellent** | Schema flexibility lets each channel store its own metadata without sparse columns or null-column bloat. |
| Customer profile with KYC + address + cards + preferences        | **Excellent**         | One document, one fetch, no joins. |
| Account statement (read-heavy, denormalised)                     | **Excellent**         | Single index scan on the embedded `from_account.account_no`; no joins. |
| Cross-account balance recomputation / reconciliation             | **Poor**              | Requires aggregating across many documents with `$group`; not a natural document-store operation. The relational model with a `SUM(CASE...)` is cleaner. |
| Multi-step ACID transfer (debit + credit + audit)                | **Acceptable**        | MongoDB 4.0+ supports multi-document ACID transactions, but at a latency cost vs. PostgreSQL. |
| Compliance audit across all transactions in a date range         | **Good**              | Handled by the parallel `audit_logs` time-series collection, not the embedded array. |
| Ad-hoc analytics with joins across customers / accounts / txns   | **Poor**              | MongoDB's `$lookup` is significantly slower than PostgreSQL's hash join for analytics. Use the relational warehouse or a columnar store. |

## 4. Comparison with the relational model

| Dimension                  | PostgreSQL (Portfolio 1)                       | MongoDB (Portfolio 4)                              |
|----------------------------|------------------------------------------------|----------------------------------------------------|
| Schema enforcement         | Strong (DDL, types, CHECK constraints)         | Optional JSON-schema validator; weaker than SQL CHECK |
| Normalisation              | 3NF / BCNF required to avoid anomalies         | Denormalisation is idiomatic; duplication is the cost |
| Joins                      | Cheap (B-tree + hash join)                     | `$lookup` is slower; embedding is preferred          |
| Multi-row ACID             | Native, fast                                   | Native since 4.0; single-document atomicity was always native |
| Read latency for a transaction statement | 2–3 index lookups + heap fetches | 1 index lookup, document returned in one fetch       |
| Write latency              | 1 INSERT into `transaction` + 1 INSERT into `transaction_log` | 1 INSERT into `transactions` (audit events embedded) |
| Storage cost               | Lower (no duplication)                         | Higher (snapshots duplicated)                        |
| Schema evolution           | Requires `ALTER TABLE`; may rewrite the table | `updateMany` with `$set`; no schema migration needed |
| Suitability for SwiftPay   | Best as the **system of record**              | Best for the **operational read path** and **schema-flexible transaction metadata** |

## 5. Suitability conclusion

For SwiftPay, MongoDB is **not** a replacement for PostgreSQL. The relational database remains the system of record because:

1. Multi-step ACID transfers, balance constraints, and reconciliation queries are first-class in PostgreSQL and awkward in MongoDB.
2. The relational normalisation protects against the data-integrity risks that are fatal in banking (a duplicated balance snapshot could drift from the truth).

MongoDB **is**, however, the right tool for two adjacent workloads:

1. The **operational read path** — denormalised customer profile and transaction statement, fetched in a single document read by the mobile app.
2. The **schema-flexible transaction metadata path** — different payment channels store different metadata fields without forcing the relational schema to grow dozens of nullable columns.

A production SwiftPay deployment would therefore run **both**: PostgreSQL as the authoritative system of record, MongoDB as a derived read model kept in sync via change-data-capture (e.g. Debezium → Kafka → MongoDB Sink Connector). This pattern is sometimes called *CQRS with polyglot persistence* and is the standard architecture for modern fintech back-ends such as Monzo, Nubank, and Stripe.

---

End of Portfolio 4 suitability analysis.
