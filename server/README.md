# CareBridge District Sync Server

The bridge between the offline-first phone app and your central **MariaDB**.

```
Phone (SQLite, source of truth)                This server               MariaDB
  every write commits locally          POST /api/sync            INSERT ... ON DUPLICATE
  + queues an outbox row      ──────▶  (Bearer token)   ──────▶  KEY UPDATE (idempotent)
  syncs when there is signal           validates + whitelists     + audit row in sync_log
```

The phone **never** talks to MariaDB directly — that would put database
credentials inside the app. It only knows this HTTP endpoint and a bearer token.

---

## 1. Prerequisites

- **Node.js 18+** (`node --version`)
- **MariaDB** running and reachable (you already have this)

## 2. Create the database schema

Load `schema.sql` into MariaDB. It creates the `carebridge` database and all
tables (idempotent — safe to re-run):

```bash
mysql -u root -p < schema.sql
```

## 3. Create a least-privilege database user

Do **not** let the sync server connect as `root`. Give it only the verbs it
needs, on only this database. If the server were ever compromised, the attacker
could write records but could not drop tables, alter the schema, or read other
databases.

```sql
CREATE USER 'carebridge_sync'@'localhost' IDENTIFIED BY 'CHANGE_ME_strong_password';
GRANT SELECT, INSERT, UPDATE, DELETE ON carebridge.* TO 'carebridge_sync'@'localhost';
FLUSH PRIVILEGES;
```

> If the server runs on a *different* machine than MariaDB, replace
> `'localhost'` with the server's host (e.g. `'carebridge_sync'@'10.0.0.5'`).

## 4. Install and configure

```bash
cd server
npm install
cp .env.example .env
```

Edit `.env`:

| Variable         | Value                                                        |
|------------------|--------------------------------------------------------------|
| `DB_HOST`        | MariaDB host (usually `127.0.0.1`)                           |
| `DB_PORT`        | MariaDB port (usually `3306`)                                |
| `DB_USER`        | `carebridge_sync`                                            |
| `DB_PASSWORD`    | the password from step 3                                     |
| `DB_NAME`        | `carebridge`                                                 |
| `PORT`           | API port, e.g. `3000`                                        |
| `SYNC_API_TOKEN` | a long random secret — generate one with the command below   |

Generate a strong token:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

**Remember this token** — you will paste the same value into each phone's
*Me → Sync settings → API token*.

## 5. Run

```bash
npm start
```

On success you will see:

```
MariaDB at 127.0.0.1:3306 is reachable.
CareBridge sync server listening on port 3000.
```

If it cannot reach MariaDB it exits immediately and tells you why — it will not
run in a half-broken state.

## 6. Connect the phone

1. Find this machine's local IP (e.g. `ipconfig` → `192.168.1.10`).
2. On the phone: **Me → Sync settings**.
3. **Server URL**: `http://192.168.1.10:3000`
4. **API token**: the `SYNC_API_TOKEN` from `.env`.
5. Tap **Test connection** — it should report *Reached the server (HTTP 200)*.
6. Tap **Save**. The app switches from demonstration mode to real sync, and the
   banner on the dashboard starts reporting records as they upload.

> The phone and this machine must be on the **same network** for a local demo.
> Make sure your firewall allows the chosen port.

## 7. Verify it works end to end

**Easiest — no phone needed.** With the server running, push a handful of
realistic sample records through the exact same HTTP path the app uses, then
look at them in your `mysql` terminal:

```bash
node scripts/seed-demo.js
```

```
ok   households            hh-demo-001
ok   persons               person-mother-001
...
```

```sql
SELECT id, name, community FROM carebridge.households;
SELECT reference_code, urgency, status FROM carebridge.referrals;
SELECT entity_table, entity_id, operation FROM carebridge.sync_log ORDER BY id DESC LIMIT 6;
```

If these rows land, the app's rows will land too — it is the same contract.

**Or by hand** — send one record shaped exactly like the app does:

```bash
curl -i -X POST http://localhost:3000/api/sync \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
        "entity_table": "households",
        "entity_id": "test-hh-1",
        "operation": "insert",
        "payload": {
          "id": "test-hh-1",
          "name": "Test household",
          "region": "Northern",
          "district": "Karaga",
          "community": "Gushegu",
          "created_by": "test-worker",
          "created_at": "2026-08-01T09:00:00.000",
          "updated_at": "2026-08-01T09:00:00.000"
        },
        "queued_at": "2026-08-01T09:00:00.000",
        "client_version": "1.0.0"
      }'
```

Expect `HTTP/1.1 200` and `{"ok":true,...}`. Then confirm it landed:

```sql
SELECT * FROM carebridge.households WHERE id = 'test-hh-1';
SELECT * FROM carebridge.sync_log ORDER BY id DESC LIMIT 1;
```

Sending the **same curl twice** should still leave exactly one row (idempotent).

---

## Security design notes (for reviewers)

- **No SQL injection by construction.** Table and column names only ever come
  from the whitelist in `src/tables.js`; every value is bound as a `?`
  parameter via prepared statements. Client input can never name a table or
  column.
- **Bearer token, constant-time compared** (`src/auth.js`). No token → 401.
  The server fails closed if no token is configured.
- **Credentials never reach the server.** The app strips `pin_hash`/`pin_salt`
  from sync payloads, and those columns do not exist here.
- **PHI-free audit trail.** Every write is logged to `sync_log` (table, id,
  operation, when) but never the payload itself.
- **Least-privilege DB user** (step 3) and **no stack traces** in responses.
- **Idempotent upserts** mean a retried send can never duplicate a child.

## Two deliberate architectural decisions

1. **No foreign keys in MariaDB.** The phone's outbox sends by *priority*, so an
   urgent referral can arrive before the routine household it belongs to. A sink
   that rejected on FK violation would make the app permanently abandon a valid
   record (the app treats 4xx as "never retry"). Integrity is already enforced
   at the source — the phone's SQLite runs with `PRAGMA foreign_keys = ON`. The
   central DB is an eventually-consistent reporting aggregate: it keeps the
   indexes (fast queries) and drops the constraints (tolerant ingest).
2. **Dates stored as the exact ISO-8601 text** the phone sends — no timezone or
   format conversion, nothing lost.

## Status-code contract (must stay in sync with the app)

| Code | Meaning to the phone                                    |
|------|---------------------------------------------------------|
| 2xx  | Accepted — mark the record synced.                      |
| 4xx  | Invalid record — stop retrying, show a human.           |
| 5xx  | Server/network problem — keep the record, retry later.  |

> **Production note:** for anything beyond a local demo, put this behind HTTPS
> (e.g. nginx + Let's Encrypt) so PHI and the token are encrypted in transit,
> and rotate the token periodically.
