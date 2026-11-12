#!/usr/bin/env python3
"""SwiftPay P3 - two-session concurrency demos (real output, nothing simulated).
Two real database sessions race to withdraw NGN 8,000 from an account holding NGN 10,000."""
import threading, time, sys, psycopg2
from psycopg2 import errors
DSN = "dbname=swiftpay"
AMT = 8000
def conn(iso=None):
    c = psycopg2.connect(DSN)
    if iso: c.set_session(isolation_level=iso)
    return c
adm = conn(); adm.autocommit = True; cur = adm.cursor()
ids = []
for n in ("DEMO-RACE-0001", "DEMO-RACE-0002"):
    cur.execute("DELETE FROM account WHERE account_number=%s", (n,))
    cur.execute("""INSERT INTO account(account_number,customer_id,branch_id,account_type,opening_balance,balance)
                   SELECT %s, customer_id, branch_id, 'SAVINGS', 10000, 10000 FROM account ORDER BY account_id LIMIT 1
                   RETURNING account_id""", (n,))
    ids.append(cur.fetchone()[0])
A, B = ids
def reset():
    cur.execute("UPDATE account SET balance=10000 WHERE account_id IN (%s,%s)", (A, B))
def bal(i=A):
    cur.execute("SELECT balance FROM account WHERE account_id=%s", (i,)); return cur.fetchone()[0]
def run2(f1, f2):
    t = [threading.Thread(target=f1), threading.Thread(target=f2)]
    t[0].start(); time.sleep(0.3); t[1].start()
    for x in t: x.join()

print("PART 1 - THE BUG: read the balance, check it, then write it back (no lock)")
reset()
def bug(name):
    def f():
        c = conn(); k = c.cursor()
        k.execute("SELECT balance FROM account WHERE account_id=%s", (A,)); b = k.fetchone()[0]
        time.sleep(1)
        if b >= AMT:
            k.execute("UPDATE account SET balance=%s WHERE account_id=%s", (b - AMT, A)); c.commit()
            print(f"     session {name}: read {b}, wrote {b-AMT}")
    return f
run2(bug("A"), bug("B"))
print(f"  >>> BUG: two withdrawals of {AMT} succeeded from a 10000 account; balance is now {bal()} (should have been rejected).")

print("PART 2 - FIX 1: SELECT ... FOR UPDATE locks the account row")
reset()
def locked(name):
    def f():
        c = conn(); k = c.cursor()
        k.execute("SELECT balance FROM account WHERE account_id=%s FOR UPDATE", (A,)); b = k.fetchone()[0]
        time.sleep(1)
        if b >= AMT:
            k.execute("UPDATE account SET balance=%s WHERE account_id=%s", (b - AMT, A)); c.commit()
            print(f"     session {name}: read {b}, wrote {b-AMT}  (COMMIT)")
        else:
            c.rollback(); print(f"     session {name}: read {b}, insufficient funds  (ROLLBACK)")
    return f
run2(locked("A"), locked("B"))
print(f"  >>> FIXED: B waited for A, then saw the new balance. Final balance {bal()}.")

print("PART 3 - FIX 2: SERIALIZABLE, no lock at all")
reset()
def ser(name):
    def f():
        c = conn(psycopg2.extensions.ISOLATION_LEVEL_SERIALIZABLE); k = c.cursor()
        try:
            k.execute("SELECT balance FROM account WHERE account_id=%s", (A,)); b = k.fetchone()[0]
            time.sleep(1)
            k.execute("UPDATE account SET balance=%s WHERE account_id=%s", (b - AMT, A)); c.commit()
            print(f"     session {name}: COMMIT")
        except psycopg2.Error as e:
            c.rollback(); print(f"     session {name}: ERROR [{e.pgcode}]: {str(e).splitlines()[0]}")
    return f
run2(ser("A"), ser("B"))
print(f"  >>> FIXED: PostgreSQL cancelled one transaction (40001). Final balance {bal()}.")

print("PART 4 - READ COMMITTED vs REPEATABLE READ (reading a balance twice)")
for name, iso in (("READ COMMITTED", psycopg2.extensions.ISOLATION_LEVEL_READ_COMMITTED),
                  ("REPEATABLE READ", psycopg2.extensions.ISOLATION_LEVEL_REPEATABLE_READ)):
    reset(); c = conn(iso); k = c.cursor()
    k.execute("SELECT balance FROM account WHERE account_id=%s", (A,)); first = k.fetchone()[0]
    cur.execute("UPDATE account SET balance=balance-500 WHERE account_id=%s", (A,))
    k.execute("SELECT balance FROM account WHERE account_id=%s", (A,)); second = k.fetchone()[0]
    c.rollback()
    print(f"     {name}: first read {first}, second read {second}" + ("  <- changed inside ONE transaction" if first != second else "  <- same snapshot"))
reset()

print("PART 5 - DEADLOCK: two transfers lock two accounts in opposite order")
def dl(name, first, second, ordered=False):
    def f():
        c = conn(); k = c.cursor()
        try:
            if ordered:
                k.execute("SELECT 1 FROM account WHERE account_id IN (%s,%s) ORDER BY account_id FOR UPDATE", (first, second))
            else:
                k.execute("UPDATE account SET balance=balance WHERE account_id=%s", (first,))
            time.sleep(1)
            k.execute("UPDATE account SET balance=balance WHERE account_id=%s", (second,)); c.commit()
            print(f"     session {name}: COMMIT")
        except psycopg2.Error as e:
            c.rollback(); print(f"     session {name}: ERROR [{e.pgcode}]: {str(e).splitlines()[0]}")
    return f
run2(dl("A", A, B), dl("B", B, A))
print("  >>> PostgreSQL detected the cycle after deadlock_timeout (1s) and cancelled one session (40P01).")
run2(dl("A", A, B, True), dl("B", B, A, True))
print("  >>> Same two accounts, locked in account_id order: B simply waits its turn. No deadlock.")

cur.execute("DELETE FROM account WHERE account_number IN ('DEMO-RACE-0001','DEMO-RACE-0002')")
print("(demo accounts removed)")
