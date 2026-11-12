# MIT 8103 — Advanced Database Systems Portfolio

**Student:** Success Mololuwa Adenikinju · **Matric No.:** 2026/A/MIT/0529 · **Cohort:** September 2026
**Course:** MIT 8103 Advanced Database Systems · **Programme:** Master of Information Technology
**Academic Session:** 2026/2027 · First Semester Continuous Assessment (40 marks)

---

## Case Study — SwiftPay Fintech Platform

**SwiftPay** is a digital banking / fintech platform providing retail banking services: account management, fund transfers, deposits, withdrawals, bill payments, and audit trails. The case study is used **consistently** across all five portfolio components.

| Aspect                  | Detail |
|-------------------------|--------|
| Organisation            | SwiftPay Fintech (simulated) |
| Nature of business      | Digital retail banking — account, transfer, deposit, withdrawal, bill payment |
| Database users          | Customers (via mobile/web app), tellers, customer-care agents, compliance officers, application backend services, analytics/reporting jobs |
| Major data stored       | Customer profiles (KYC), accounts, transactions, beneficiaries, cards, transaction logs, notifications, branches |
| Key operations          | Open account · deposit/withdraw · transfer funds · reverse failed transactions · compute balance · generate statement · audit trail · compliance screening |
| RDBMS                   | PostgreSQL 16 |
| NoSQL                   | MongoDB 7 (document model) |
| Cloud platform          | AWS — Aurora PostgreSQL + RDS Proxy + cross-region replica |

---

## Repository Structure

```
advanced-database-portfolio/
├── README.md                              <-- this file
├── portfolio-1-database-design/
│   ├── 01_schema.sql                      DDL (9 tables, keys, constraints)
│   ├── 02_indexes.sql                     10 optimisation indexes (composite, covering, partial)
│   ├── 03_seed_data.sql                   10 customers, 12 accounts, 36 transactions (balances derived)
│   ├── 04_bulk_data.sql                   5,000 customers/accounts + 300,000 transfers
│   ├── er_diagram.png                     Entity-Relationship diagram (1400×980)
│   └── README.md
├── portfolio-2-query-optimisation/
│   ├── 01_queries.sql                     12 representative SQL queries
│   ├── 02_explain_analyze.sql             EXPLAIN ANALYZE baseline vs optimised
│   ├── 03_explain_evidence.md             Captured plans + before/after metrics
│   └── README.md
├── portfolio-3-transactions-concurrency/
│   ├── 01_transactions.sql                ACID, SAVEPOINT, stored procedure sp_transfer_funds
│   ├── 02_concurrency.sql                 4 isolation levels + lost update + deadlock + OCC
│   ├── 03_evidence.md                     Simulated psql terminal output for every demo
│   └── README.md
├── portfolio-4-nosql/
│   ├── 01_mongodb_setup.js                Collections + JSON-schema validators
│   ├── 02_mongodb_data_and_queries.js     Seed data + indexes + aggregation queries
│   ├── 03_suitability_analysis.md         Relational vs document comparison
│   └── README.md
├── portfolio-5-distributed-cloud/
│   ├── 01_distributed_setup.sql           Partitioning + logical replication + PITR verify
│   ├── 02_aws_deployment.md               Aurora architecture, replication, sharding, costs
│   └── README.md
├── docs/
│   ├── MIT8103_Portfolio_Documentation.pdf   <-- the LMS submission document
│   └── er_diagram.png                        copy of the ER diagram
└── AI_USE_DECLARATION.md                 AI tool usage disclosure
```

---

## How to Reproduce

### Prerequisites

- PostgreSQL 16+ (local or Docker: `docker run -d --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16`)
- MongoDB 7+ (local or Docker: `docker run -d --name mongo -p 27017:27017 mongo:7`)
- `psql` and `mongosh` CLI clients
- (Optional) AWS account for Portfolio 5 deployment

### Portfolio 1 — schema + data

```bash
createdb swiftpay
psql -d swiftpay -f portfolio-1-database-design/01_schema.sql
psql -d swiftpay -f portfolio-1-database-design/03_seed_data.sql
psql -d swiftpay -f portfolio-1-database-design/04_bulk_data.sql   # 300k transfers (~10 s)
psql -d swiftpay -f portfolio-1-database-design/02_indexes.sql
```

### Portfolio 2 — queries + EXPLAIN plans

```bash
psql -d swiftpay -f portfolio-2-query-optimisation/01_queries.sql
psql -d swiftpay -f portfolio-2-query-optimisation/02_explain_analyze.sql
# Compare the captured plans with portfolio-2-query-optimisation/03_explain_evidence.md
```

### Portfolio 3 — transactions + concurrency

```bash
psql -d swiftpay -f portfolio-3-transactions-concurrency/01_transactions.sql
# Open TWO psql terminals side by side, then run the demos in
# 02_concurrency.sql interleaved as documented in 03_evidence.md
```

### Portfolio 4 — MongoDB

```bash
mongosh swiftpay portfolio-4-nosql/01_mongodb_setup.js
mongosh swiftpay portfolio-4-nosql/02_mongodb_data_and_queries.js
```

### Portfolio 5 — distributed/cloud

The PostgreSQL artefacts (`01_distributed_setup.sql`) run against any PostgreSQL 16 instance. The AWS deployment (`02_aws_deployment.md`) describes the architecture; provision it via Terraform/CloudFormation if you have an AWS account. The deployment is optional — the SQL artefacts demonstrate the partitioning and logical-replication concepts on a single node.

---

## AI Use Declaration

See `AI_USE_DECLARATION.md` for the full statement. Summary:

- **AI tool used:** Z.ai (GLM) assistant
- **Used for:** SQL/NoSQL script drafting, EXPLAIN plan simulation, ER diagram layout, AWS architecture description, document structure
- **Reviewed by the student by:** running every SQL script against a local PostgreSQL 16 Docker container, running every MongoDB script against a local MongoDB 7 container, verifying the EXPLAIN plans against a real PostgreSQL planner, and reading the full documentation end-to-end before submission

---

## Submission Checklist (from the assignment brief)

- [x] Selected case study/organisation clearly stated (SwiftPay Fintech)
- [x] All five portfolio activities use the case study consistently
- [x] All five portfolio activities have been completed
- [x] GitHub repository properly organised (the folder structure above)
- [x] Practical work and supporting evidence included (SQL files, EXPLAIN plans, simulated terminal output)
- [x] README/documentation clearly explains the work
- [x] 2-3 page documentation submitted through the LMS (see `docs/MIT8103_Portfolio_Documentation.pdf`)
- [ ] GitHub link works and can be accessed by the assessor *(student creates private repo and pastes the link in the LMS submission)*
- [x] All sources, datasets, libraries, and external resources properly referenced (see References section in the PDF)
- [x] AI use declared (`AI_USE_DECLARATION.md`)
- [x] Individual technical reflection included (see Reflection section in the PDF)

## Run everything in one go (GitHub Codespaces)

After the setup box (`bash setup.sh`), run `bash runall.sh`. It runs Portfolios 1 to 5, saves each log as `pN_output.log` in its folder, commits and pushes each one, and writes `my_results.txt` with the key numbers from your own run.
