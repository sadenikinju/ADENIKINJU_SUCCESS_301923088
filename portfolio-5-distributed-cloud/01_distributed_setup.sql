-- =====================================================================
-- MIT 8103 - Portfolio 5: Distributed & Cloud Database Exercise
-- Case Study: SwiftPay Fintech Platform
-- File: 01_distributed_setup.sql
-- Engine: PostgreSQL 16 on AWS RDS (multi-AZ) + Aurora PostgreSQL
-- =====================================================================
--
-- This file contains the *PostgreSQL-level* artefacts of the distributed
-- deployment discussed in README.md and 02_aws_deployment.md:
--
--   * Read-replica-aware application routing (pgpool / HAProxy)
--   * Partitioning the `transaction` table by month (sharding within
--     a single RDS instance as a stepping stone to full sharding)
--   * Cross-region logical replication for the customer master table
--   * Connection pooling configuration
--   * Backup verification (PITR) procedure
--
-- The IaC (Terraform + CloudFormation) for the AWS resources lives in
-- 02_aws_deployment.md.
-- =====================================================================

-- =====================================================================
-- 1. PARTITIONING the `transaction` table by month
--    This is the first step towards horizontal scaling. Queries that
--    filter by date hit only one partition; old partitions can be
--    archived to cold storage with DETACH + S3 export.
-- =====================================================================

-- Convert the existing transaction table to a partitioned table.
-- In production this is done via pg_partman; the DDL below is the
-- manual equivalent for clarity.

BEGIN;

-- 1a. Rename the existing table
ALTER TABLE transaction RENAME TO transaction_old;

-- 1b. Create the parent table partitioned by RANGE on initiated_at
CREATE TABLE transaction (
    transaction_id BIGSERIAL,
    reference_no   VARCHAR(20)  NOT NULL,
    from_account_id BIGINT,
    to_account_id   BIGINT,
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    currency       CHAR(3)      DEFAULT 'NGN',
    type_id        SMALLINT     NOT NULL,
    status         VARCHAR(15)  DEFAULT 'PENDING'
                   CHECK (status IN ('PENDING','COMPLETED','FAILED','REVERSED')),
    channel        VARCHAR(20),
    description    VARCHAR(200),
    initiated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    completed_at   TIMESTAMPTZ,
    reversal_of    BIGINT,
    PRIMARY KEY (transaction_id, initiated_at),
    -- On a partitioned table every UNIQUE key must include the partition key,
    -- so reference_no is unique per (reference_no, initiated_at). Global
    -- uniqueness of reference_no is a known trade-off of partitioning.
    UNIQUE (reference_no, initiated_at)
) PARTITION BY RANGE (initiated_at);

-- 1c. Create monthly partitions for the next 6 months + a default
CREATE TABLE transaction_2026_09 PARTITION OF transaction
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE transaction_2026_10 PARTITION OF transaction
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE transaction_2026_11 PARTITION OF transaction
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE transaction_2026_12 PARTITION OF transaction
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE transaction_2027_01 PARTITION OF transaction
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
CREATE TABLE transaction_2027_02 PARTITION OF transaction
    FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');
CREATE TABLE transaction_default PARTITION OF transaction DEFAULT;

-- 1d. Migrate existing data from the renamed table
INSERT INTO transaction (transaction_id, reference_no, from_account_id, to_account_id,
                         amount, currency, type_id, status, channel, description,
                         initiated_at, completed_at, reversal_of)
SELECT transaction_id, reference_no, from_account_id, to_account_id,
       amount, currency, type_id, status, channel, description,
       initiated_at, completed_at, reversal_of
FROM   transaction_old;

-- 1e. Drop the old table. CASCADE also drops the old foreign key from
--     transaction_log, which still points at transaction_old.
DROP TABLE transaction_old CASCADE;

-- 1f. Recreate foreign keys (must point at the partitioned parent)
ALTER TABLE transaction
    ADD CONSTRAINT fk_txn_type
    FOREIGN KEY (type_id) REFERENCES transaction_type(type_id);
-- NOTE: transaction_log -> transaction can no longer be a plain FK.
-- The partitioned parent's primary key is (transaction_id, initiated_at),
-- and a foreign key must reference a complete unique key. Options are to
-- add initiated_at to transaction_log, or enforce the link in the
-- application/trigger. This is a real trade-off of partitioning.
-- ALTER TABLE transaction_log
--     ADD CONSTRAINT fk_log_txn
--     FOREIGN KEY (transaction_id) REFERENCES transaction(transaction_id)
--     ON DELETE CASCADE;

-- 1g. Recreate the indexes on every partition (PostgreSQL does this
--     automatically when CREATE INDEX is run on the partitioned parent)
CREATE INDEX idx_txn_from_acct_date
    ON transaction(from_account_id, initiated_at DESC);
CREATE INDEX idx_txn_to_acct_date
    ON transaction(to_account_id, initiated_at DESC);
CREATE INDEX idx_txn_completed_partial
    ON transaction(initiated_at DESC)
    WHERE status = 'COMPLETED';

COMMIT;

-- Verify partition pruning works
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM transaction
 WHERE initiated_at >= '2026-09-01' AND initiated_at < '2026-10-01'
   AND status = 'COMPLETED';
-- Expected plan: only `transaction_2026_09` is scanned, not the parent.


-- =====================================================================
-- 2. LOGICAL REPLICATION  -  publish customer master to a read replica
--    in a different AWS region. SwiftPay's DR region is eu-west-1.
-- =====================================================================

-- On the PRIMARY (ap-southeast-1):
CREATE PUBLICATION swiftpay_customer_pub
    FOR TABLE customer, account, branch;

-- On the REPLICA (eu-west-1):
-- (run after schema is in place)
-- CREATE SUBSCRIPTION swiftpay_customer_sub
--     CONNECTION 'host=swiftpay-primary.ap-southeast-1.rds.amazonaws.com
--                 port=5432 user=replicator password=***'
--     PUBLICATION swiftpay_customer_pub
--     WITH (copy_data = true, create_slot = true);

-- Check publication status
SELECT * FROM pg_publication;
SELECT * FROM pg_stat_replication;


-- =====================================================================
-- 3. READ-REplica routing - mark the application's read-only sessions
--    The pgpool-II / HAProxy rule is: SET transaction_read_only = on
--    routes to the reader endpoint. The SQL below is the contract.
-- =====================================================================

-- Application issues this at the start of any read-only transaction:
SET transaction_read_only = on;
SELECT balance FROM account WHERE account_number = 'SP0001110001';
-- pgpool routes this to one of the read replicas. Writes automatically
-- go to the writer endpoint (the primary).


-- =====================================================================
-- 4. POINT-IN-TIME RECOVERY (PITR) verification
--    AWS RDS automated backups retain the last 35 days of WAL.
--    Verify by restoring to a test instance and running a count.
-- =====================================================================

-- This is a documentation of the recovery procedure:
-- 1. aws rds restore-db-instance-to-point-in-time \
--      --source-db-instance-identifier swiftpay-prod \
--      --target-db-instance-identifier swiftpay-pit-verify \
--      --restore-time 2026-10-04T10:00:00Z \
--      --db-instance-class db.r6g.large
-- 2. Wait for "available" status (~15-20 minutes for 50 GB)
-- 3. Run the count below to verify data is present at that PIT.

SELECT COUNT(*) AS txn_count_at_pit
FROM   transaction
WHERE  initiated_at < '2026-10-04T10:00:00Z';


-- =====================================================================
-- 5. CONNECTION POOLING via RDS Proxy (PgBouncer-compatible)
--    Connection string change only - no schema work needed.
-- =====================================================================
-- Old (direct):
--   postgresql://app:pw@swiftpay-primary.cluster-xyz.ap-southeast-1.rds.amazonaws.com:5432/swiftpay
-- New (via RDS Proxy):
--   postgresql://app:pw@swiftpay-proxy.proxy-xyz.ap-southeast-1.rds.amazonaws.com:5432/swiftpay
--
-- The proxy maintains a pool of warm connections to the primary and
-- reduces connection-establishment latency from ~50ms to <5ms. The
-- Lambda / Fargate compute does not need the pgxpool library any more.

-- =====================================================================
-- End of 01_distributed_setup.sql
-- =====================================================================
