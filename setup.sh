#!/usr/bin/env bash
# =============================================================================
# setup.sh — Environment bootstrap for MIT 8103 Advanced Database Systems
# Portfolio (SwiftPay case study).
#
# Installs and starts:
#   * PostgreSQL 16  (with btree_gist, pg_partman available via contrib)
#   * MongoDB 8.0    (mongod, listening on 127.0.0.1:27017)
#
# Target environment: GitHub Codespaces (Ubuntu 24.04 image).
#
# Codespaces-specific rules honoured:
#   * `sudo -u postgres` is NOT used (the codespace user can only sudo to root).
#     Instead we use `sudo runuser -u postgres -- ...`.
#   * The conflicting yarn apt source is removed BEFORE apt-get update.
#   * TCP logins to Postgres require a password, so every script connects
#     through the Unix socket (host=/var/run/postgresql) using peer auth.
#   * postgres_fdw is intentionally NOT installed/used anywhere in the repo.
#
# Run from the repo root inside a Codespace terminal:
#   bash setup.sh
# =============================================================================
set -euo pipefail

echo "==================================================================="
echo " SwiftPay — Portfolio environment bootstrap"
echo " Student : Success Adenikinju"
echo " Matric  : 2026/A/MIT/0529"
echo "==================================================================="

# ---------------------------------------------------------------------------
# 1. Remove the conflicting yarn source list entry (breaks apt-get update
#    on recent Codespaces Ubuntu images because the GPG key is missing).
# ---------------------------------------------------------------------------
if [ -f /etc/apt/sources.list.d/yarn.list ]; then
  echo "[setup] Removing /etc/apt/sources.list.d/yarn.list (known Codespaces blocker)"
  sudo rm -f /etc/apt/sources.list.d/yarn.list
fi

# ---------------------------------------------------------------------------
# 2. apt-get update + install base packages + official PostgreSQL / MongoDB
#    repo keys so we get exactly PostgreSQL 16 and MongoDB 8.0 (not the
#    older defaults shipped with Ubuntu).
# ---------------------------------------------------------------------------
echo "[setup] apt-get update"
sudo apt-get update -y

echo "[setup] Installing base packages (curl, ca-certificates, gnupg, lsb-release, python3-pip, poppler-utils)"
sudo apt-get install -y curl ca-certificates gnupg lsb-release python3-pip poppler-utils postgresql-client-16 jq

# --- PostgreSQL 16 official repo -------------------------------------------
echo "[setup] Adding PostgreSQL official APT repo (PGDG) for PostgreSQL 16"
if ! dpkg -s postgresql-16 >/dev/null 2>&1; then
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] \
http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
    sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y postgresql-16 postgresql-contrib
else
  echo "[setup] postgresql-16 already installed"
fi

# --- MongoDB 8.0 official repo ---------------------------------------------
echo "[setup] Adding MongoDB 8.0 official APT repo"
if ! dpkg -s mongodb-org >/dev/null 2>&1; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org
else
  echo "[setup] mongodb-org already installed"
fi

# ---------------------------------------------------------------------------
# 3. Python driver libs used by the bulk-data generators (P1 + P4).
#    --break-system-packages is required on the PEP 668 Codespaces image.
# ---------------------------------------------------------------------------
echo "[setup] Installing Python drivers (psycopg2-binary, pymongo)"
pip3 install --user --break-system-packages psycopg2-binary pymongo 2>/dev/null || \
  pip3 install --break-system-packages psycopg2-binary pymongo

# ---------------------------------------------------------------------------
# 4. Start PostgreSQL 16 cluster. Codespaces ships PG under
#    /etc/postgresql/16/main/ and pg_ctl at /usr/lib/postgresql/16/bin/pg_ctl.
#    pg_ctlcluster is the Ubuntu wrapper and is the simplest way to start.
# ---------------------------------------------------------------------------
echo "[setup] Starting PostgreSQL 16 cluster"
sudo pg_ctlcluster 16 main start || sudo pg_ctlcluster 16 main restart

# Make sure the postgres superuser has a database and can be reached over the
# Unix socket via peer auth (the codespace default user is `root` in sudo
# context; we create a matching role so the portfolio scripts can connect as
# `postgres` through the socket without a password).
echo "[setup] Ensuring 'swiftpay' role + database exist (Unix-socket peer auth)"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'swiftpay') THEN
    CREATE ROLE swiftpay LOGIN SUPERUSER CREATEDB;
  END IF;
END$$;
SQL

# A fresh codespace often has no `swiftpay` database; create it so every
# run_pN.sh can `DROP DATABASE` + recreate without permission errors.
# (\gexec only works in a script/heredoc, not inside psql -c "…")
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE DATABASE swiftpay OWNER swiftpay'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'swiftpay')\gexec
SQL

# Python scripts run as YOUR Linux user (codespace) over the Unix socket, and
# peer authentication only lets a Linux user log in as the database role of
# the same name — so create that role too.
OS_USER="$(id -un)"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${OS_USER}') THEN
    CREATE ROLE "${OS_USER}" LOGIN SUPERUSER;
  END IF;
END \$\$;
SQL

# Show all dates/times in Lagos time (WAT, UTC+1).
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER DATABASE swiftpay SET timezone TO 'Africa/Lagos';"

# btree_gist ships in postgresql-contrib; make sure it is available.
sudo runuser -u postgres -- psql -d swiftpay -v ON_ERROR_STOP=0 -c \
  "CREATE EXTENSION IF NOT EXISTS btree_gist;"

# ---------------------------------------------------------------------------
# 5. Start MongoDB 8.0. Codespaces does NOT auto-start mongod.
# ---------------------------------------------------------------------------
echo "[setup] Starting MongoDB 8.0 (mongod)"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb || true

# Start mongod as the mongodb system user; bind only to localhost for safety.
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo runuser -u mongodb -- /usr/bin/mongod \
    --dbpath /data/db \
    --logpath /var/log/mongodb/mongod.log \
    --bind_ip 127.0.0.1 \
    --port 27017 \
    --fork
else
  echo "[setup] mongod already running"
fi

# Wait for MongoDB to accept connections.
echo "[setup] Waiting for MongoDB to accept connections..."
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1; then
    echo "[setup] MongoDB is up"
    break
  fi
  sleep 1
done

# ---------------------------------------------------------------------------
# 6. Final verification — show versions + reachable sockets.
# ---------------------------------------------------------------------------
echo ""
echo "[setup] === Verification ==="
sudo runuser -u postgres -- psql -c "SELECT version();" | head -3
echo ""
mongosh --quiet --eval "db.version()"
echo ""
echo "PostgreSQL socket : /var/run/postgresql/.s.PGSQL.5432"
echo "MongoDB endpoint  : mongodb://127.0.0.1:27017"
echo ""
echo "[setup] DONE. You can now run each portfolio:"
echo "    bash portfolio-1-database-design/run_p1.sh"
echo "    bash portfolio-2-query-optimisation/run_p2.sh"
echo "    bash portfolio-3-transactions-concurrency/run_p3.sh"
echo "    bash portfolio-4-nosql/run_p4.sh"
echo "    bash portfolio-5-distributed-cloud/run_p5.sh"
echo "==================================================================="
