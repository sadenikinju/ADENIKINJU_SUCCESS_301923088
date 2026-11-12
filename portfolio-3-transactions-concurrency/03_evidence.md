> ⚠️ **SIMULATED OUTPUT — DO NOT SUBMIT AS IS.** This file was AI-generated, not captured from a real run. Run the scripts yourself and replace everything below with your **real** terminal output and screenshots.

# Portfolio 3 — Transactions & Concurrency Evidence

This file captures the simulated terminal output produced when the scripts `01_transactions.sql` and `02_concurrency.sql` are executed against the SwiftPay database in two concurrent `psql` sessions. The outputs demonstrate ACID behaviour, the four ANSI isolation levels, lost-update prevention, deadlock detection, and optimistic concurrency control.

Each block below is a textual "screenshot" — a faithful representation of what `psql` prints when the script is run.

---

## Terminal session — atomic transfer (T1)

```
swiftpay=# \i 01_transactions.sql
BEGIN
 account_id
-----------
         1
         3
(2 rows)

UPDATE 1
UPDATE 1
INSERT 0 1
INSERT 0 1
COMMIT
```

The two `UPDATE 1` acknowledgements and the two `INSERT 0 1` acknowledgements all happen inside a single transaction. If any statement had failed, PostgreSQL would have rolled back all four statements atomically — the database would never have ended in a state where the debit landed but the credit did not.

---

## Terminal session — failed transfer (T2)

```
swiftpay=# BEGIN;
BEGIN
swiftpay=*# SELECT balance FROM account WHERE account_number = 'SP0001110001' FOR UPDATE;
  balance
----------
 210000.00
(1 row)

swiftpay=*# UPDATE account SET balance = balance - 99999999
swiftpay-*#  WHERE account_number = 'SP0001110001';
ERROR:  new row for relation "account" violates check constraint "chk_balance_limit"
DETAIL:  Failing row contains (1, SP0001110001, 1, 1, SAVINGS, -99789999.00, NGN, ACTIVE, ...).
swiftpay=!# COMMIT;
ROLLBACK
swiftpay=#
```

**Observations**

- The `CHECK` constraint `chk_balance_limit` fires because a SAVINGS account cannot go negative.
- PostgreSQL automatically transitions the transaction to an *aborted* state (`psql` prompt switches from `*` to `!`).
- The `COMMIT` is interpreted as `ROLLBACK` because the transaction is already in an error state.
- Result: balance is unchanged. **Atomicity is preserved.**

---

## Terminal session — SAVEPOINT partial rollback (T3)

```
swiftpay=# BEGIN;
BEGIN
swiftpay=*# INSERT INTO notification (customer_id, message, channel)
swiftpay-*# VALUES (1, 'Promotional: 5% cashback on bills this week', 'SMS');
INSERT 0 1
swiftpay=*# SAVEPOINT sp_before_risky_insert;
SAVEPOINT
swiftpay=*# BEGIN
swiftpay-#     INSERT INTO transaction (reference_no, from_account_id, to_account_id,
swiftpay-#                              amount, type_id, status)
swiftpay-#     VALUES ('TXN-20261105-DEMO03', 99999, 1, 1000, 1, 'COMPLETED');
NOTICE:  Caught FK violation - rolling back to savepoint
END
swiftpay=*# ROLLBACK TO SAVEPOINT sp_before_risky_insert;
ROLLBACK
swiftpay=*# COMMIT;
COMMIT
swiftpay=# SELECT message FROM notification WHERE message LIKE 'Promotional%';
                       message
------------------------------------------------------
 Promotional: 5% cashback on bills this week
(1 row)
```

The notification row survives because it was inserted *before* the SAVEPOINT, while the invalid transaction row was rolled back to the savepoint without aborting the whole transaction.

---

## Terminal session — calling `sp_transfer_funds` (T4)

```
swiftpay=# CREATE SEQUENCE IF NOT EXISTS txn_ref_seq START 1;
CREATE SEQUENCE
swiftpay=# BEGIN;
BEGIN
swiftpay=*# CALL sp_transfer_funds('SP0001110001','SP0001110003', 7500.00,
swiftpay-*#                         'Procedure-driven demo transfer', 'MOBILE', NULL);
    p_reference
----------------------
 TXN-20261105-102301-0001
(1 row)

CALL
swiftpay=*# COMMIT;
COMMIT
swiftpay=# SELECT reference_no, amount, status, description
swiftpay-# FROM   transaction WHERE reference_no LIKE 'TXN-20261105-102301%';
      reference_no       | amount  |  status   |         description
--------------------------+---------+-----------+------------------------------
 TXN-20261105-102301-0001 | 7500.00 | COMPLETED | Procedure-driven demo transfer
(1 row)

swiftpay=# SELECT account_number, balance FROM account
swiftpay-# WHERE account_number IN ('SP0001110001','SP0001110003');
 account_number  |  balance
-----------------+------------
 SP0001110001    | 202500.00
 SP0001110003    | 437500.00
(2 rows)

swiftpay=# SELECT event_type, occurred_at, actor
swiftpay-# FROM transaction_log
swiftpay-# WHERE transaction_id = (SELECT transaction_id FROM transaction
swiftpay(#                              WHERE reference_no='TXN-20261105-102301-0001')
swiftpay-# ORDER BY occurred_at;
 event_type  |       occurred_at        |   actor
-------------+--------------------------+------------
 INITIATED   | 2026-11-05 10:23:01+01   | demo_user
 COMPLETED   | 2026-11-05 10:23:01+01   | demo_user
(2 rows)
```

The procedure debited the source, credited the destination, inserted the transaction row, and wrote two audit-log entries — all inside one CALL. From the caller's perspective the operation is atomic: either the entire CALL succeeds, or nothing persists.

---

## Isolation-level demonstrations (C1–C4)

### C2 — READ COMMITTED permits non-repeatable read

```
----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN ISOLATION LEVEL
READ COMMITTED;
BEGIN
swiftpay=*# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 202500.00                       swiftpay=# BEGIN;
(1 row)                           BEGIN
                                  swiftpay=*# UPDATE account SET balance
                                   = balance + 10000
                                  swiftpay-*#  WHERE account_number='SP0001110001';
                                  UPDATE 1
                                  swiftpay=*# COMMIT;
                                  COMMIT
swiftpay=*# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 212500.00   <-- different value!
(1 row)
swiftpay=*# COMMIT;
COMMIT
```

The two `SELECT` statements inside Session A returned different values for the same row. This is the **non-repeatable read** anomaly permitted at READ COMMITTED.

### C3 — REPEATABLE READ prevents non-repeatable read

```
----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN ISOLATION LEVEL
REPEATABLE READ;
BEGIN
swiftpay=*# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 212500.00                       swiftpay=# BEGIN;
(1 row)                           BEGIN
                                  swiftpay=# UPDATE account SET balance
                                   = balance + 10000
                                  swiftpay-#  WHERE account_number='SP0001110001';
                                  UPDATE 1
                                  swiftpay=# COMMIT;
                                  COMMIT
swiftpay=*# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 212500.00   <-- still the snapshot value!
(1 row)
swiftpay=*# COMMIT;
COMMIT
swiftpay=# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 222500.00   <-- only after COMMIT does A see the new value
(1 row)
```

Session A operated against a snapshot taken at its first read. Subsequent reads inside the same transaction returned the snapshot value, not the latest committed value. After A commits, a fresh read returns the new value.

### C4 — SERIALIZABLE aborts the conflicting transaction

```
swiftpay=# UPDATE account SET balance = 5000
 WHERE account_number='SP0001110006';
UPDATE 1

----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN ISOLATION LEVEL
SERIALIZABLE;
BEGIN                                swiftpay=# BEGIN ISOLATION LEVEL
                                     SERIALIZABLE;
                                     BEGIN
swiftpay=*# SELECT balance FROM
 account WHERE account_number=
 'SP0001110006';
  balance
----------
   5000.00                        swiftpay=*# SELECT balance FROM
(1 row)                            account WHERE account_number=
                                   'SP0001110006';
                                     balance
                                    ----------
                                      5000.00
                                    (1 row)
swiftpay=*# UPDATE account SET
 balance = balance - 4000
 WHERE account_number=
 'SP0001110006';
UPDATE 1                            swiftpay=*# UPDATE account SET
                                     balance = balance - 4000
                                    swiftpay-*#  WHERE account_number=
                                     'SP0001110006';
                                    UPDATE 1     <-- both UPDATEs land
swiftpay=*# COMMIT;                              (no constraint fires yet)
COMMIT
                                     swiftpay=*# COMMIT;
                                     ERROR:  could not serialize access
                                     due to read/write dependencies
                                     among transactions
                                     DETAIL:  Reason code: Canceled on
                                     identification as a pivot during
                                     write conflict.
                                     ROLLBACK
swiftpay=# SELECT balance FROM account
 WHERE account_number='SP0001110006';
  balance
----------
   1000.00
(1 row)
```

Both sessions read 5000 and tried to debit 4000. The CHECK constraint would not have fired (4000 ≤ 5000), so without serialisation control both transactions would have committed, leaving the balance at 1000 — a combined debit of 8000 from an account that only had 5000. SERIALIZABLE detected the conflict at COMMIT time and aborted Session B.

---

## Lost-update demonstration (C5)

### Variant A — naive (an update is silently lost)

```
----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN;
BEGIN                                swiftpay=# BEGIN;
                                     BEGIN
swiftpay=*# SELECT balance FROM
 account WHERE account_number=
 'SP0001110001';
  balance                       swiftpay=*# SELECT balance FROM
----------                      account WHERE account_number=
 222500.00                       'SP0001110001';
(1 row)                              balance
                                    ----------
                                     222500.00
                                    (1 row)
swiftpay=*# UPDATE account SET
 balance = 222500 + 1000
 WHERE account_number=
 'SP0001110001';
UPDATE 1                            swiftpay=*# UPDATE account SET
                                     balance = 222500 + 1000
                                    swiftpay-*#  WHERE account_number=
                                     'SP0001110001';
                                    UPDATE 1
swiftpay=*# COMMIT;                  swiftpay=*# COMMIT;
COMMIT                              COMMIT
swiftpay=# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 223500.00       <-- only +1000 - the other +1000 was lost
(1 row)
```

### Variant B — `SELECT … FOR UPDATE` prevents the lost update

```
----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN;
BEGIN                                swiftpay=# BEGIN;
                                     BEGIN
swiftpay=*# SELECT balance FROM
 account WHERE account_number=
 'SP0001110001' FOR UPDATE;
  balance                       swiftpay=*# SELECT balance FROM
----------                      account WHERE account_number=
 223500.00                       'SP0001110001' FOR UPDATE;
(1 row)                            (BLOCKS - Session A holds the row lock)
swiftpay=*# UPDATE account SET
 balance = 223500 + 1000
 WHERE account_number=
 'SP0001110001';
UPDATE 1
swiftpay=*# COMMIT;
COMMIT                                <-- Session B's SELECT now returns
                                         balance = 224500.00 (the new value)
                                     swiftpay=*# UPDATE account SET
                                      balance = 224500 + 1000
                                     swiftpay-*#  WHERE account_number=
                                      'SP0001110001';
                                     UPDATE 1
                                     swiftpay=*# COMMIT;
                                     COMMIT
swiftpay=# SELECT balance FROM account
 WHERE account_number='SP0001110001';
  balance
----------
 225500.00       <-- both +1000 increments persisted
(1 row)
```

The `FOR UPDATE` clause acquires a row-level lock that blocks Session B's read until Session A commits or rolls back. The second increment is computed on the *post-Session-A* balance, so both updates are preserved.

---

## Deadlock demonstration (C6)

```
----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN;
BEGIN                                swiftpay=# BEGIN;
                                     BEGIN
swiftpay=*# UPDATE account SET
 balance = balance - 1000
 WHERE account_number=
 'SP0001110001';
UPDATE 1                            swiftpay=*# UPDATE account SET
                                     balance = balance - 1000
                                    swiftpay-*#  WHERE account_number=
                                     'SP0001110003';
                                    UPDATE 1
swiftpay=*# UPDATE account SET
 balance = balance + 1000
 WHERE account_number=
 'SP0001110003';                   swiftpay=*# UPDATE account SET
(BLOCKS)                            balance = balance + 1000
                                    swiftpay-*#  WHERE account_number=
                                     'SP0001110001';
                                    (BLOCKS)
ERROR:  deadlock detected
DETAIL:  Process 1234 waits for ShareLock on
transaction 5678; blocked by process 5679.
Process 5679 waits for ShareLock on
transaction 5677; blocked by process 1234.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,1) in
relation "account"
swiftpay=!# ROLLBACK;                swiftpay=*# UPDATE 1
ROLLBACK                            swiftpay=*# COMMIT;
                                    COMMIT
```

PostgreSQL's deadlock detector wakes up roughly once per second, scans the wait-for graph for cycles, and aborts one of the transactions in the cycle. The aborted session receives SQLSTATE `40P01` (`deadlock_detected`) and must retry.

The fix used in the `sp_transfer_funds` procedure is to lock both account rows up-front in ascending `account_id` order. Any two transfers — regardless of direction — then acquire locks in the same order, so no cycle can ever form.

---

## Optimistic concurrency control (C7)

```
swiftpay=# ALTER TABLE account ADD COLUMN IF NOT EXISTS version_no
 INTEGER DEFAULT 1;
ALTER TABLE

----- Session A -----                  ----- Session B -----
swiftpay=# BEGIN;                   swiftpay=# BEGIN;
BEGIN                               BEGIN
swiftpay=*# SELECT balance, version_no
 FROM account
 WHERE account_number='SP0001110001';
  balance  | version_no
----------+------------
 225500.00 |          1
(1 row)
                                    swiftpay=*# SELECT balance, version_no
                                     FROM account
                                     WHERE account_number='SP0001110001';
                                      balance  | version_no
                                    ----------+------------
                                     225500.00 |          1
                                    (1 row)
swiftpay=*# UPDATE account SET
 balance = balance + 1000,
 version_no = version_no + 1
 WHERE account_number='SP0001110001'
   AND version_no = 1;
UPDATE 1    <-- 1 row updated
swiftpay=*# COMMIT;
COMMIT
                                    swiftpay=*# UPDATE account SET
                                     balance = balance + 1000,
                                     version_no = version_no + 1
                                    swiftpay-*#  WHERE account_number=
                                     'SP0001110001' AND version_no = 1;
                                    UPDATE 0    <-- 0 rows - the version
                                                  changed under us
                                    swiftpay=*# ROLLBACK;
                                    ROLLBACK
                                    (Application tells the user:
                                     "row was modified by another user,
                                      please reload and retry")
swiftpay=# ALTER TABLE account DROP COLUMN IF EXISTS version_no;
ALTER TABLE
```

Optimistic concurrency control trades a slightly higher application-level retry rate for the absence of held row locks during the user's think time — appropriate for HTTP-based flows where the client may pause for tens of seconds before saving.

---

End of Portfolio 3 evidence.
