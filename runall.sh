#!/usr/bin/env bash
# runall.sh - runs Portfolios 1-5 in order, saves each log, commits and pushes each,
# then writes my_results.txt.   Usage:  bash runall.sh      (or: bash runall.sh 3  to restart from P3)
set -uo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
START="${1:-1}"
KIT="$(find "$HOME/kit" -maxdepth 3 -type d -name 'portfolio-1-*' 2>/dev/null | head -1 | xargs -r dirname)"
if [ -z "$KIT" ]; then
  Z="$(ls "$REPO"/*[Ff][Ii][Xx][Ee][Dd]*.zip 2>/dev/null | head -1)"
  [ -n "$Z" ] && mkdir -p "$HOME/kit" && unzip -oq "$Z" -d "$HOME/kit"
  KIT="$(find "$HOME/kit" -maxdepth 3 -type d -name 'portfolio-1-*' | head -1 | xargs -r dirname)"
fi
[ -z "$KIT" ] && { echo "!!! Cannot find the project files (~/kit). Send Joseph this message."; exit 1; }
echo "[runall] using $KIT"
# Codespaces stops background programs when it sleeps: start PostgreSQL and MongoDB again if needed
pg_lsclusters 2>/dev/null | grep -q online || sudo pg_ctlcluster 16 main start 2>/dev/null || true
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- /usr/bin/mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null 2>&1 || true
for i in $(seq 1 30); do mongosh --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1 && break; sleep 1; done
psql -d swiftpay -c 'SELECT 1' >/dev/null 2>&1 || { echo "[runall] database missing - running setup.sh first"; bash "$REPO/setup.sh" || { echo "!!! setup.sh failed - send Joseph the last lines"; exit 1; }; }
python3 -c 'import psycopg2' 2>/dev/null || { pip3 install psycopg2-binary 2>/dev/null || pip3 install --user psycopg2-binary 2>/dev/null || pip3 install --break-system-packages psycopg2-binary 2>/dev/null || pip3 install --user --break-system-packages psycopg2-binary 2>/dev/null || sudo apt-get install -y python3-psycopg2; }
python3 -c 'import psycopg2' || { echo "!!! psycopg2 could not be installed - send Joseph this line"; exit 1; }

P1=portfolio-1-database-design; P2=portfolio-2-query-optimisation; P3=portfolio-3-transactions-concurrency; P4=portfolio-4-nosql; P5=portfolio-5-distributed-cloud
FOLDERS=("$P1" "$P2" "$P3" "$P4" "$P5")
step() { # N, then commands read from the function named pN
  local N="$1"; local F="${FOLDERS[$((N-1))]}"
  echo; echo "================ PORTFOLIO $N ($F) ================"
  rm -rf "$REPO/$F.new"; cp -r "$KIT/$F" "$REPO/$F.new" && rm -rf "$REPO/$F" && mv "$REPO/$F.new" "$REPO/$F"
  cd "$REPO/$F"
  "p$N" 2>&1 | tee "p${N}_output.log"; local rc=${PIPESTATUS[0]}
  cd "$REPO"
  if [ "$rc" -ne 0 ]; then echo "!!! P$N FAILED - send Joseph the file $F/p${N}_output.log"; return 1; fi
  git add -A >/dev/null 2>&1; git commit -qm "Portfolio $N: scripts and real output" >/dev/null 2>&1; git push -q >/dev/null 2>&1 || true
  echo "[runall] P$N done and committed"
}
Q="psql -d swiftpay -X -v ON_ERROR_STOP=1"
p1() { set -e; $Q -f 01_schema.sql -q; $Q -f 03_seed_data.sql -q; $Q -f 04_bulk_data.sql -q; $Q -f 02_indexes.sql -q
  echo "=== P1 row counts ==="; $Q -c "SELECT (SELECT count(*) FROM customer) customers, (SELECT count(*) FROM account) accounts, (SELECT count(*) FROM transaction) transactions, (SELECT count(*) FROM card) cards;"; }
p2() { set -e; $Q -f 01_queries.sql -o /dev/null -q; echo "=== P2 EXPLAIN ANALYZE before/after ==="; psql -d swiftpay -X -f 02_explain_analyze.sql; }
p3() { psql -d swiftpay -X -f 01_transactions.sql; echo "=== P3 two-session concurrency demos ==="; python3 race_demos.py 2>&1 | tee race_demos_output.log; }
p4() { set -e; mongosh swiftpay --quiet 01_mongodb_setup.js; mongosh swiftpay --quiet 02_mongodb_data_and_queries.js; echo "=== P4 bulk data + index demo ==="; mongosh swiftpay --quiet 03_bulk_and_index_demo.js; }
p5() { set -e; $Q -f 01_distributed_setup.sql 2>&1 | tee partition_output.log; echo "=== P5 streaming replica ==="; bash 02_replica_setup.sh 2>&1 | tee replication_output.log; sudo runuser -u postgres -- psql -X -d swiftpay -f 03_replica_tests.sql 2>&1 | tee -a replication_output.log; }
for N in 1 2 3 4 5; do [ "$N" -ge "$START" ] && { step "$N" || exit 1; }; done
bash collect_results.sh && { code my_results.txt 2>/dev/null || true; }
echo "[runall] ALL DONE - my_results.txt is open. Copy everything in it and send it to Joseph."
