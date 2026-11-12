#!/usr/bin/env bash
# collect_results.sh - gathers the key REAL numbers from your own run into my_results.txt
cd "$(dirname "$0")"
OUT=my_results.txt
P1=portfolio-1-database-design; P2=portfolio-2-query-optimisation; P3=portfolio-3-transactions-concurrency; P4=portfolio-4-nosql; P5=portfolio-5-distributed-cloud
Q="psql -d swiftpay -X -q"
{
echo "MY RESULTS — SwiftPay — $(date '+%Y-%m-%d %H:%M %Z')"
echo
echo "===== P1: row counts ====="
$Q -c "SELECT (SELECT count(*) FROM customer) customers, (SELECT count(*) FROM account) accounts, (SELECT count(*) FROM transaction) transactions, (SELECT count(*) FROM card) cards;"
echo "===== P2: BEFORE / AFTER (EXPLAIN ANALYZE, ms) ====="
if [ -f $P2/p2_output.log ]; then
  T=($(grep -oP 'Execution Time: \K[0-9.]+' $P2/p2_output.log)); L=(Q1_statement Q3_top_customers Q5_reference_lookup Q8_suspicious)
  printf "%-22s %12s %12s %9s\n" Query "BEFORE (ms)" "AFTER (ms)" speed-up
  for i in 0 1 2 3; do awk -v n="${L[$i]}" -v b="${T[$i]}" -v a="${T[$((i+4))]}" 'BEGIN{printf "%-22s %12.3f %12.3f %8.1fx\n", n, b, a, b/a}'; done
  echo "--- plans (before -> after) ---"
  grep -E "Seq Scan on transaction t|Bitmap Index Scan on idx_txn|Index Scan using idx_txn_reference" $P2/p2_output.log | sed 's/(cost.*//' | head -12
else echo "(no p2_output.log)"; fi
echo
echo "===== P3: transactions + race demos ====="
grep -E "ERROR:|COMMIT|ROLLBACK|SAVEPOINT|TXN-" $P3/p3_output.log 2>/dev/null | grep -v "^PART" | head -14
cat $P3/race_demos_output.log 2>/dev/null || echo "(no race_demos_output.log)"
echo
echo "===== P4: MongoDB ====="
grep -E "transactions in collection|^BEFORE|^AFTER|^Stage|^Docs|^Time ms" $P4/p4_output.log 2>/dev/null || echo "(no p4_output.log)"
echo
echo "===== P5: partitions + pruning ====="
$Q -c "SELECT tableoid::regclass AS partition, count(*) AS rows FROM transaction GROUP BY 1 ORDER BY 1;"
grep -E "Scan on transaction_|Execution Time|Planning Time" $P5/partition_output.log 2>/dev/null | sed 's/(cost.*//' | head -6
echo "===== P5: replica ====="
grep -E "PRIMARY|REPLICA|read-only|RP0001|P5-REPLICA|streaming|primary_is_in_recovery|replica_is_in_recovery|^ f|^ t|marker_rows|bytes_behind" $P5/replication_output.log 2>/dev/null | head -24
echo
echo "===== GitHub ====="
git remote get-url origin 2>&1
git log --oneline 2>&1 | head -12
} > "$OUT" 2>&1
echo "Saved $OUT"
