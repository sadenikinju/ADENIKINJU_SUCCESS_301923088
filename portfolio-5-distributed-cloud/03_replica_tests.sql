-- P5 - streaming replica behaviour tests (SwiftPay). Run as the postgres OS user over the Unix socket.
\set ON_ERROR_STOP off
\echo === Replica tests ===
\connect -reuse-previous=off swiftpay - /var/run/postgresql 5433
SELECT 'REPLICA' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\echo --- T1. Attempt an INSERT on the REPLICA (port 5433). Must be rejected ---
INSERT INTO branch (branch_name, branch_code, address, city) VALUES ('P5 replica write test', 'RW0001', 'n/a', 'Lagos');
\connect -reuse-previous=off swiftpay - /var/run/postgresql 5432
SELECT 'PRIMARY' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\echo --- T2. Insert a marker row on the PRIMARY (5432), then read it on the REPLICA (5433) ---
INSERT INTO branch (branch_name, branch_code, address, city) VALUES ('P5-REPLICA-PROOF', 'RP0001', 'n/a', 'Lagos');
SELECT pg_sleep(1);
SELECT application_name, state, sync_state, sent_lsn, replay_lsn, (sent_lsn - replay_lsn) AS bytes_behind FROM pg_stat_replication;
\connect -reuse-previous=off swiftpay - /var/run/postgresql 5433
SELECT branch_name, branch_code FROM branch WHERE branch_code = 'RP0001';
\connect -reuse-previous=off swiftpay - /var/run/postgresql 5432
DELETE FROM branch WHERE branch_code = 'RP0001';
SELECT pg_sleep(1);
\connect -reuse-previous=off swiftpay - /var/run/postgresql 5433
SELECT count(*) AS marker_rows_left_on_replica FROM branch WHERE branch_code = 'RP0001';
