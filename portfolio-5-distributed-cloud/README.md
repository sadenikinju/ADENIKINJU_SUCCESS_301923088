# Portfolio 5 — Distributed and Cloud Database Exercise

**Case study:** SwiftPay Fintech Platform
**Cloud platform:** AWS — Aurora PostgreSQL + RDS Proxy + cross-region replica
**Marks:** 6 / 40

## Deliverables

| File | Purpose |
|------|---------|
| `01_distributed_setup.sql` | PostgreSQL-level artefacts: monthly partitioning of `transaction`, logical replication publication, read-replica routing, PITR verification |
| `02_aws_deployment.md`     | Architecture, replication topology, sharding strategy, consistency model, availability matrix, backup policy, monitoring, cost estimate |

## Architecture summary

```
Application (ECS/Fargate, ap-southeast-1)
        │
   RDS Proxy (PgBouncer-compatible, IAM auth)
        │
   ┌────┴─────────────┬─────────────────┐
   ▼                  ▼                 ▼
Aurora primary    Aurora replica 1   Aurora replica 2 (cross-region,
(ap-SE-1a)        (ap-SE-1b,         eu-west-1, async DR)
 quorum 4/6)       sync standby)
```

## Non-functional requirements met

| Requirement                  | Aurora capability                                |
|------------------------------|--------------------------------------------------|
| 99.99% availability SLA      | Multi-AZ synchronous storage + auto failover < 30 s |
| Zero data loss on AZ failure | 4-of-6 quorum write                              |
| Read scaling 10× writes      | Up to 15 read replicas behind one reader endpoint |
| DR in a second region        | Cross-region async replica + Route 53 failover   |
| PITR within 35 days          | Continuous WAL archive + daily snapshot          |
| Sub-100 ms p99 reads         | Read replica + RDS Proxy warm pool               |
| CBN 7-year retention         | Quarterly snapshot to S3 Glacier                 |

## Sharding roadmap

1. **Now (≤ 11 M txns/year)** — single Aurora cluster, monthly partitions on `transaction`.
2. **Year 2-3 (~50 M txns/year)** — add read replicas; partition granularity moves to weekly.
3. **Year 4+ (> 50 M txns/day)** — shard by `customer_id` using Citus on Aurora or self-hosted PostgreSQL. Co-locates all of a customer's data on one shard; 95% of customer-facing queries become single-shard.

## Consistency model summary

| Operation | Consistency | Justification |
|-----------|-------------|---------------|
| Writes to primary | Strong (linearisable) | Aurora 4/6 quorum |
| Reads from primary | Strong | Read-your-own-write |
| Reads from in-region replica | ≤10 ms lag | Acceptable for statements; balance-after-transfer reads use primary |
| Reads from cross-region replica | ≤1 s lag | DR and analytics only |
| Cross-shard reads | Session-consistent within a shard | Global linearisability would require 2PC — accepted trade-off |

## How to run the SQL artefacts

```bash
psql -d swiftpay -f portfolio-5-distributed-cloud/01_distributed_setup.sql
```

The script converts the `transaction` table from a heap to a monthly-partitioned table, sets up a logical replication publication, and demonstrates partition pruning via `EXPLAIN`. The AWS architecture is described in `02_aws_deployment.md` and can be provisioned separately via Terraform if an AWS account is available.
