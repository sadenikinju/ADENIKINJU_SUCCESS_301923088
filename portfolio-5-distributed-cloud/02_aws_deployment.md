# Portfolio 5 — Distributed & Cloud Database Exercise

## AWS RDS PostgreSQL + Aurora deployment for SwiftPay

This document describes a production-grade distributed database deployment for SwiftPay on AWS, covering replication, high availability, sharding strategy, consistency guarantees, and operational procedures.

---

## 1. Target architecture

```
                         ┌──────────────────────────┐
                         │   Application (ECS /       │
                         │   Fargate / Lambda)        │
                         │   in ap-southeast-1        │
                         └─────────────┬────────────┘
                                       │
                                       ▼
                         ┌──────────────────────────┐
                         │   RDS Proxy (PgBouncer-   │
                         │   compatible)             │
                         │   - connection pooling    │
                         │   - failover detection    │
                         └─────────────┬────────────┘
                                       │
                  ┌────────────────────┴────────────────────┐
                  ▼                                          ▼
        ┌─────────────────────┐                    ┌─────────────────────┐
        │  Writer endpoint    │                    │  Reader endpoint    │
        │  (Aurora primary,   │                    │  (round-robin to    │
        │   ap-southeast-1a)  │                    │   2 Aurora replicas)│
        └──────────┬──────────┘                    └─────────────────────┘
                   │ synchronous, multi-AZ
                   ▼
        ┌─────────────────────┐
        │  Aurora replica 1   │  ← standby in ap-southeast-1b (failover target)
        │  ap-southeast-1b    │
        └─────────────────────┘
                   │
                   │ asynchronous, cross-region
                   ▼
        ┌─────────────────────┐
        │  Aurora replica 2   │  ← DR replica in eu-west-1 (for read &
        │  eu-west-1          │     disaster recovery)
        └─────────────────────┘

        Backups:
        - Automated daily snapshot (35-day retention)
        - Continuous WAL archive → S3 (PITR to any second within 35 days)
        - Manual snapshot before every schema migration
```

## 2. Service selection: Aurora PostgreSQL vs vanilla RDS PostgreSQL

| Capability                           | RDS PostgreSQL | Aurora PostgreSQL | SwiftPay choice |
|--------------------------------------|----------------|-------------------|-----------------|
| Multi-AZ synchronous standby         | Yes (one standby) | Yes (6 copies, 3 AZs × 2 copies) | **Aurora** — survives an AZ loss with zero data loss |
| Read replicas                        | Up to 5        | Up to 15          | **Aurora** — needed for read scaling |
| Replica lag                          | ~100 ms        | <10 ms typically  | **Aurora** — banking reads need fresh data |
| Automatic failover time              | 60–120 s       | <30 s typically   | **Aurora** — lower RTO |
| Storage auto-scaling                 | Yes (manual steps) | Yes (continuous) | **Aurora** — no provisioning needed |
| Cost                                 | Lower          | ~20% higher       | Accept the premium for the HA + read-scale benefits |
| Cross-region replica                 | Yes (async)    | Yes (async, fast) | Both work; Aurora's lower lag is preferred |

SwiftPay uses **Aurora PostgreSQL 16** for the writer and two in-region read replicas, plus one cross-region read replica in `eu-west-1` for disaster recovery.

## 3. Replication topology

### 3.1 Synchronous replication (in-region, multi-AZ)

Aurora stores six copies of every storage chunk across three Availability Zones (two copies per AZ). Writes are acknowledged to the application only after a quorum (4 of 6) of copies has been written. This delivers:

- **RPO = 0** for an AZ failure (no committed transaction is lost).
- **RTO < 30 s** for an automatic primary failover (Aurora promotes a read replica without rebuilding storage).

### 3.2 Asynchronous replication (cross-region, DR)

Aurora's cross-region replica mirrors the primary's WAL stream to `eu-west-1`. Replication lag is typically under one second. The DR replica can be promoted to a standalone primary if the entire `ap-southeast-1` region fails — providing:

- **RPO ≤ 1 s** for a full region failure.
- **RTO < 5 min** (promotion + application DNS switch via Route 53).

### 3.3 Logical replication (selective, business-level)

In addition to storage-level replication, SwiftPay publishes the `customer`, `account`, and `branch` tables via PostgreSQL logical replication to a separate analytics database. This decouples analytical workloads from the OLTP primary and lets the analytics database run on a different PostgreSQL major version if needed.

```sql
CREATE PUBLICATION swiftpay_customer_pub
    FOR TABLE customer, account, branch;
```

## 4. Sharding strategy

### 4.1 Within a single Aurora cluster — partitioning

The `transaction` table grows by an estimated 30 K rows per day (≈ 11 M rows/year). At this scale a single Aurora writer can still keep up, but the table becomes unwieldy for maintenance (vacuum, index rebuild). We partition it by month using PostgreSQL native declarative partitioning:

```sql
CREATE TABLE transaction ( ... )
    PARTITION BY RANGE (initiated_at);
```

Benefits:

- **Partition pruning** — a query for September transactions scans only the September partition.
- **Fast archival** — detach an old partition in milliseconds and export it to S3 Glacier via `pg_dump` or Aurora's `SELECT INTO S3`.
- **Smaller indexes per partition** — each partition's B-tree is a fraction of the size of a monolithic one, speeding up vacuum.

### 4.2 Beyond a single cluster — Citus sharding (future growth)

If transaction volume exceeds ~50 M rows/day (SwiftPay's 5-year forecast), horizontal sharding across multiple Aurora clusters is needed. The candidate sharding keys are:

| Key                       | Distribution | Problem                                                        |
|---------------------------|--------------|----------------------------------------------------------------|
| `transaction_id` (hash)   | Even         | Cross-shard query for "all transactions for account X" — bad. |
| `from_account_id` (hash)  | Skewed       | Big accounts become hot shards.                                |
| `initiated_at` (range)    | Time-based   | Recent-month shard is hot; old shards are cold (acceptable).   |
| `customer_id` (hash)      | Even         | Co-locates all of a customer's transactions on one shard — best for tenant isolation. |

The recommended shard key is **`customer_id`** (co-locating all of a customer's accounts and transactions on the same node). This makes 95% of customer-facing queries single-shard. Cross-shard queries (system-wide aggregates) fall back to a columnar analytics store.

Citus (a PostgreSQL extension, available on Aurora via the Citus Cloud managed service or self-hosted on EC2) implements this pattern with `CREATE TABLE ... USING citus_columnar DISTRIBUTED BY (customer_id);`.

## 5. Consistency model

| Operation                                  | Consistency level                | Why                                   |
|--------------------------------------------|----------------------------------|---------------------------------------|
| Writes (insert/update on primary)          | Strong (linearisable)            | Aurora quorum write of 4/6 copies     |
| Reads from primary                         | Strong                           | Read-your-own-write consistency       |
| Reads from in-region read replica          | Read-after-write may lag ≤10 ms  | Acceptable for statement reads; for "balance after a transfer" reads, the application reads from the primary |
| Reads from cross-region replica            | Eventual (≤1 s lag)              | Acceptable only for DR and analytics  |
| Cross-shard reads                          | Session-consistent within a shard | Cannot provide global linearisability across shards without 2PC — accepted trade-off |
| Analytics on the logical-replication target | Eventual (seconds behind)       | Acceptable for dashboards             |

The application code uses the routing convention:

- `SET transaction_read_only = on` → routes to a read replica (via RDS Proxy).
- Read-write transactions → writer endpoint.

Critical balance reads after a transfer use the writer endpoint, not a replica, to avoid showing a stale pre-debit balance.

## 6. Availability & failover

| Failure scenario                         | Detection         | Recovery                              | RTO        | RPO    |
|------------------------------------------|-------------------|---------------------------------------|------------|--------|
| Aurora primary node crash                | ~30 s             | Promote in-region read replica        | <30 s      | 0      |
| AZ failure                               | ~30 s             | Promote replica in another AZ         | <30 s      | 0      |
| Region failure (ap-southeast-1 down)     | Manual decision   | Promote cross-region DR replica       | <5 min     | ≤1 s   |
| RDS Proxy failure                        | ~10 s             | AWS swaps the proxy                   | <30 s      | 0      |
| Application tier failure                 | ECS health check  | Replace tasks                         | <60 s      | 0      |

Application DNS is managed by Route 53 with a weighted routing policy:

- 95% of traffic → `ap-southeast-1` writer endpoint
- 5% of traffic → `eu-west-1` (always-on read traffic; can be promoted in DR)

## 7. Backup & recovery

| Backup type                          | Schedule              | Retention     | Purpose                                  |
|--------------------------------------|-----------------------|---------------|------------------------------------------|
| Automated daily snapshot             | 03:00 UTC daily       | 35 days       | RDS/Aurora default                       |
| Continuous WAL archive               | Continuous (streamed) | 35 days       | PITR to any second within the window     |
| Manual snapshot before migration     | Pre-migration         | 90 days       | Rollback after a botched schema migration |
| Quarterly snapshot to S3 Glacier     | Quarterly             | 7 years       | Regulatory retention (CBN requirement)   |

The PITR procedure is verified monthly by restoring to a test instance and running the count query from `01_distributed_setup.sql` §4.

## 8. Connection pooling

RDS Proxy (PgBouncer-compatible) sits between the application and the Aurora cluster. It:

- Maintains a pool of warm database connections (eliminates the ~50 ms TLS handshake cost on every Lambda invocation).
- Detects primary failover and pauses connections for <30 s instead of dropping them with errors.
- Enforces IAM database authentication — no static database password in the application config.

Typical configuration:

```yaml
# Aurora cluster
DBInstanceClass:        db.r6g.2xlarge   (8 vCPU, 64 GB RAM)
Engine:                 aurora-postgresql
EngineVersion:          16.3
MultiAZ:                true
StorageType:            aurora-iopt1     (Aurora I/O-Optimised)
BackupRetentionPeriod:  35
PreferredBackupWindow:  "03:00-04:00 UTC"
PreferredMaintenanceWindow: "sun:04:00-sun:05:00"

# Read replicas
- 2 × db.r6g.large in ap-southeast-1 (reader endpoint load-balances)
- 1 × db.r6g.large in eu-west-1 (cross-region, async DR)

# RDS Proxy
ProxyName:              swiftpay-proxy
TargetRole:             read-write
ConnectionPoolConfig:
  MaxConnectionsPercent:      90
  IdleClientTimeout:          1800   (30 min)
  InitQuery:                  "SET application_name='swiftpay-app'"
RequireTLS:             true
AuthMode:               IAM_AUTH
```

## 9. Monitoring & alerting

| Metric                           | Threshold                | Action                            |
|----------------------------------|--------------------------|-----------------------------------|
| `DatabaseConnections`            | > 800 (sustained 5 min)  | Page DBA — connection leak        |
| `CPUUtilization` (writer)        | > 70% (sustained 10 min) | Scale up instance class           |
| `FreeableMemory`                 | < 4 GB                   | Page — possible OOM kill          |
| `ReplicaLag` (in-region)         | > 30 s                   | Page — replica cannot keep up     |
| `ReplicaLag` (cross-region)      | > 5 s                    | Investigate network               |
| `AuroraBinlogReplicaLag`         | > 60 s                   | Page — DR risk                    |
| `WriteLatency`                   | > 20 ms (p99)            | Page — storage degradation        |
| `Deadlocks`                      | > 10 / min               | Page — application deadlock       |
| `FreeStorageSpace`               | < 50 GB                  | Page — disk full imminent         |

Monitoring is via CloudWatch + RDS Enhanced Monitoring, with alarms wired into PagerDuty.

## 10. Cost estimate (monthly, list price, us-east-1)

| Component                                  | Monthly cost (USD) |
|--------------------------------------------|--------------------|
| Aurora primary db.r6g.2xlarge              | ~1,250             |
| Aurora replica × 2 (db.r6g.large)          | ~1,300             |
| Cross-region replica (db.r6g.large, eu-w-1)| ~720               |
| Aurora I/O-Optimised storage 500 GB        | ~625               |
| RDS Proxy                                  | ~85                |
| Backups to S3 Glacier (regulatory)         | ~30                |
| CloudWatch + alarms                        | ~25                |
| Data transfer (cross-region replication)   | ~80                |
| **Total**                                  | **~4,115 / month** |

A vanilla RDS PostgreSQL equivalent (no Aurora) would cost ~25% less but sacrifice the multi-AZ synchronous quorum, the <30 s failover, and the 15-replica scaling headroom.

## 11. Suitability conclusion

The Aurora PostgreSQL deployment described above meets SwiftPay's non-functional requirements:

| Requirement (from product spec)                | Aurora capability that satisfies it                  |
|------------------------------------------------|------------------------------------------------------|
| 99.99% availability SLA                        | Multi-AZ synchronous storage + automatic failover < 30 s |
| Zero data loss on AZ failure                   | 4-of-6 quorum write                                  |
| Read scaling to 10× write volume               | Up to 15 read replicas behind a single reader endpoint |
| Disaster recovery in a second region           | Cross-region async replica + Route 53 weighted failover |
| Point-in-time recovery within 35 days          | Continuous WAL archive + automated snapshot          |
| Sub-100 ms p99 read latency                    | Read replica + RDS Proxy warm connection pool        |
| Compliance with CBN 7-year retention           | Quarterly snapshot to S3 Glacier                     |

A self-hosted Citus or PostgreSQL-on-EC2 deployment could match the technical capability at lower list cost, but would require a dedicated DBA team for patching, replication setup, backup verification, and failover testing. For a fintech with a small engineering team, the managed-service premium is justified by the operational risk reduction.

---

End of Portfolio 5 distributed/cloud exercise.
