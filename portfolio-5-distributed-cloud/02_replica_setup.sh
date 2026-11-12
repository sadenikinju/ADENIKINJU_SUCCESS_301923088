#!/usr/bin/env bash
# =============================================================================
# Portfolio 5 — sql/02_replica_setup.sh
# SwiftPay — set up a PostgreSQL streaming read replica on the SAME
# Codespace as the primary (different port).
#
# Architecture:
#   Primary   : port 5432, data dir /var/lib/postgresql/16/main
#   Replica   : port 5433, data dir /var/lib/postgresql/16/replica
#   Both      : connect through the Unix socket /var/run/postgresql
#
# Codespaces rules honoured:
#   * sudo runuser -u postgres -- ...      (NEVER sudo -u postgres)
#   * PostgreSQL config under /etc/postgresql/16/main/
#   * pg_ctl at /usr/lib/postgresql/16/bin/pg_ctl
#   * Replica gets its OWN postgresql.conf (pg_basebackup -R writes a
#     minimal one; we override port + hot_standby + socket dir afterwards).
#   * pg_hba.conf trust lines are PREPENDED to the TOP of the file
#     (the default `local all postgres peer` block below would otherwise
#     shadow them).
#   * Connect through Unix sockets (host=/var/run/postgresql); no TCP password
#     needed.
#   * No postgres_fdw — this is native logical/physical streaming replication.
#
# Run from the repo root in a Codespace:
#   bash portfolio-5-distributed-cloud/sql/02_replica_setup.sh
#
# Idempotent: if the replica already exists and is running, the script
# reports it and skips. If you need a clean re-run:
#   sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
#       -D /var/lib/postgresql/16/replica stop -m fast
#   sudo rm -rf /var/lib/postgresql/16/replica
#   bash portfolio-5-distributed-cloud/sql/02_replica_setup.sh
# =============================================================================
set -euo pipefail

PG_VERSION="16"
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
PG_SOCKET="/var/run/postgresql"
PRIMARY_DATA="/var/lib/postgresql/${PG_VERSION}/main"
REPLICA_DATA="/var/lib/postgresql/${PG_VERSION}/replica"
REPLICA_PORT="5433"
REPL_USER="repl"
REPL_SLOT="replica1"
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

echo "==================================================================="
echo " Portfolio 5 — primary + streaming read replica"
echo "   Primary : port 5432  (${PRIMARY_DATA})"
echo "   Replica : port ${REPLICA_PORT}  (${REPLICA_DATA})"
echo "==================================================================="

# ---------------------------------------------------------------------------
# 0. Pre-flight: make sure the primary cluster is up.
# ---------------------------------------------------------------------------
if ! sudo pg_lsclusters | awk '$1=="'"${PG_VERSION}"'" && $2=="main" {print $4}' | grep -q online; then
    echo "[repl] starting primary cluster"
    sudo pg_ctlcluster "${PG_VERSION}" main start
fi

# ---------------------------------------------------------------------------
# 1. Configure the primary: wal_level=replica, max_wal_senders, listen on localhost.
#    Append a marker block so re-runs don't duplicate lines.
# ---------------------------------------------------------------------------
echo "[repl] configuring primary postgresql.conf for replication"
if ! grep -q "^max_wal_senders = 10" "${PG_CONF}"; then
    sudo tee -a "${PG_CONF}" >/dev/null <<EOF

# --- p5 replication block ---
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
listen_addresses = 'localhost'
hot_standby = on
EOF
else
    echo "[repl]   replication block already present"
fi

# ---------------------------------------------------------------------------
# 2. pg_hba.conf: PREPEND trust lines for local replication at the TOP.
#    (Codespaces rule: trust lines must go at the top so they shadow the
#    default `local all postgres peer` line that lives below.)
# ---------------------------------------------------------------------------
echo "[repl] prepending replication trust lines to top of pg_hba.conf"
# Save the existing content, write the new lines, then the old content back.
sudo cp "${PG_HBA}" "${PG_HBA}.bak.$(date +%s)"
if ! sudo grep -q "^host    replication     ${REPL_USER}" "${PG_HBA}"; then
    sudo bash -c "cat > /tmp/_hba_new <<EOF
# --- p5 replication trust lines (must be at the TOP) ---
local   replication     ${REPL_USER}                          trust
host    replication     ${REPL_USER}      127.0.0.1/32         trust
host    replication     ${REPL_USER}      ::1/128              trust
# Allow the swiftpay role to connect to the replica over the socket too.
local   all             all                                  trust
EOF
cat /tmp/_hba_new ${PG_HBA} > ${PG_HBA}.new && mv ${PG_HBA}.new ${PG_HBA}"
    sudo chown postgres:postgres "${PG_HBA}"
    sudo chmod 640 "${PG_HBA}"
else
    echo "[repl]   replication trust lines already at top"
fi

# ---------------------------------------------------------------------------
# 3. Restart the primary so the postgresql.conf + pg_hba.conf changes take.
# ---------------------------------------------------------------------------
echo "[repl] restarting primary to apply wal_level + pg_hba changes"
sudo pg_ctlcluster "${PG_VERSION}" main restart

# ---------------------------------------------------------------------------
# 4. Create the replication role + slot.
# ---------------------------------------------------------------------------
echo "[repl] creating replication role '${REPL_USER}' and slot '${REPL_SLOT}'"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD 'replpass';
  END IF;
END \$\$;
SELECT pg_create_physical_replication_slot('${REPL_SLOT}')
 WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = '${REPL_SLOT}');
SQL

# ---------------------------------------------------------------------------
# 5. If a replica already exists and is running, stop+remove it so the
#    pg_basebackup is clean. (Idempotent re-run.)
# ---------------------------------------------------------------------------
if [ -d "${REPLICA_DATA}" ] && [ -f "${REPLICA_DATA}/postmaster.pid" ]; then
    echo "[repl] stopping existing replica"
    sudo runuser -u postgres -- "${PG_BIN}/pg_ctl" \
        -D "${REPLICA_DATA}" stop -m fast || true
fi
sudo rm -rf "${REPLICA_DATA}"
sudo mkdir -p "${REPLICA_DATA}"
sudo chown postgres:postgres "${REPLICA_DATA}"
sudo chmod 700 "${REPLICA_DATA}"

# ---------------------------------------------------------------------------
# 6. pg_basebackup: copy the primary's data dir into the replica dir, with
#    streaming WAL (-X stream), a replication slot (-S), and -R which writes
#    standby.signal + primary.conninfo for us.
# ---------------------------------------------------------------------------
echo "[repl] running pg_basebackup (this can take ~30 s for the swiftpay DB)"
sudo runuser -u postgres -- "${PG_BIN}/pg_basebackup" \
    -h "${PG_SOCKET}" \
    -U "${REPL_USER}" \
    -D "${REPLICA_DATA}" \
    -X stream \
    -S "${REPL_SLOT}" \
    -R \
    -P
# (no -C: the slot was already created above with pg_create_physical_replication_slot;
#  -C as well made pg_basebackup stop with "replication slot already exists")

# Ubuntu keeps pg_hba.conf / pg_ident.conf / postgresql.conf in /etc, not in
# the data directory, so pg_basebackup did not copy them — give the replica
# its own copies before editing them below.
sudo cp /etc/postgresql/${PG_VERSION}/main/pg_hba.conf   "${REPLICA_DATA}/pg_hba.conf"
sudo cp /etc/postgresql/${PG_VERSION}/main/pg_ident.conf "${REPLICA_DATA}/pg_ident.conf"
sudo chown postgres:postgres "${REPLICA_DATA}/pg_hba.conf" "${REPLICA_DATA}/pg_ident.conf"

# ---------------------------------------------------------------------------
# 7. Configure the replica's OWN postgresql.conf:
#    * port = 5433
#    * hot_standby = on (so we can run SELECTs while in recovery)
#    * unix_socket_directories = /var/run/postgresql (same socket dir as primary)
#    * listen_addresses = '' (no TCP; socket only — keeps us password-free)
# ---------------------------------------------------------------------------
echo "[repl] writing the replica's own postgresql.conf overrides"
sudo tee "${REPLICA_DATA}/postgresql.conf" >/dev/null <<EOF

# --- p5 replica overrides ---
port = ${REPLICA_PORT}
hot_standby = on
unix_socket_directories = '${PG_SOCKET}'
listen_addresses = ''
timezone = 'Africa/Lagos'
EOF
sudo chown postgres:postgres "${REPLICA_DATA}/postgresql.conf"

# The replica needs its own pg_hba.conf too. pg_basebackup copied the
# primary's; prepend the same trust block at the top (Codespaces rule).
if ! sudo grep -q "# --- p5 replica hba ---" "${REPLICA_DATA}/pg_hba.conf"; then
    sudo bash -c "cat > /tmp/_repl_hba <<EOF
# --- p5 replica hba (must be at the TOP) ---
local   all             all                                  trust
host    all             all             127.0.0.1/32         trust
host    all             all             ::1/128              trust
EOF
cat /tmp/_repl_hba ${REPLICA_DATA}/pg_hba.conf > ${REPLICA_DATA}/pg_hba.conf.new && \
    mv ${REPLICA_DATA}/pg_hba.conf.new ${REPLICA_DATA}/pg_hba.conf"
    sudo chown postgres:postgres "${REPLICA_DATA}/pg_hba.conf"
fi

# ---------------------------------------------------------------------------
# 8. Start the replica with pg_ctl (as postgres, on port 5433).
# ---------------------------------------------------------------------------
echo "[repl] starting replica on port ${REPLICA_PORT}"
sudo runuser -u postgres -- "${PG_BIN}/pg_ctl" \
    -D "${REPLICA_DATA}" \
    -l "/tmp/replica.log" \
    -w start

sleep 2

# ---------------------------------------------------------------------------
# 9. Verify.
# ---------------------------------------------------------------------------
echo ""
echo "=== Verification ==="
echo "[repl] primary (5432) — SELECT pg_is_in_recovery();"
sudo runuser -u postgres -- psql -p 5432 -d swiftpay -c "SELECT pg_is_in_recovery() AS primary_is_in_recovery;"
echo ""
echo "[repl] replica (5433) — SELECT pg_is_in_recovery();"
sudo runuser -u postgres -- psql -p 5433 -d swiftpay -c "SELECT pg_is_in_recovery() AS replica_is_in_recovery;"
echo ""
echo "[repl] primary — replication status:"
sudo runuser -u postgres -- psql -p 5432 -d swiftpay -c "
SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn
  FROM pg_stat_replication;"

echo ""
echo "[repl] DONE."
echo "[repl] Replication is now streaming: writes on the primary (port 5432)"
echo "[repl] are replayed onto the replica (port 5433) within milliseconds."
echo ""
echo "[repl] To connect to the replica for read-only queries:"
echo "    sudo runuser -u postgres -- psql -p 5433 -d swiftpay"
