# Backups

## Purpose

Documents the backup strategy for the Task Management API: what is backed up, how to run and restore backups, the retention policy, and how to automate the process.

## Prerequisites

- SSH access to the VPS
- Docker and Docker Compose running with the production stack up
- The `.env` file loaded (or `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` exported in the shell)

---

## 1. What Is — and Is Not — Backed Up

| Data store | Backed up? | Rationale |
|------------|-----------|-----------|
| **PostgreSQL** | ✅ Yes | Authoritative source of truth for all task records. Loss is unrecoverable. |
| **Redis** | ❌ No | Used exclusively as a short-lived read-through cache (30-second TTL). On restart or data loss Redis is repopulated on the next request. No user data lives only in Redis. |
| **Application container** | ❌ No | Stateless — rebuilt from the Docker image on every deployment. |
| **NGINX / Certbot config** | ❌ No | Configuration is version-controlled in the repository. Certbot certificates are renewed automatically; they can be re-issued if lost. |

---

## 2. Where Backups Are Stored

| Item | Path |
|------|------|
| Backup files | `/opt/backups/postgres/` |
| Filename format | `backup_YYYYMMDD_HHMMSS.sql.gz` |
| Backup log | `/var/log/taskapi-backup.log` |

Backups are stored on the VPS local filesystem. The directory is created automatically by the script on first run.

> [!WARNING]
> Local-only backups are a single point of failure. For production, consider syncing `/opt/backups/postgres/` to an off-site destination (e.g. an S3-compatible bucket via `rclone` or `aws s3 sync`) after each successful run.

---

## 3. Running a Manual Backup

SSH into the VPS, navigate to the repo root, source the environment, and run the script:

```bash
cd /opt/app/fastAPI-redis-stack        # adjust to your actual repo path on the VPS
source .env                             # load POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
bash scripts/backup.sh
```

**Expected output** (written to stdout and appended to `/var/log/taskapi-backup.log`):

```
2026-07-01T02:30:00Z [INFO] Using container: fastapi-redis-stack-postgres-1
2026-07-01T02:30:00Z [INFO] Starting backup of database 'taskdb' → /opt/backups/postgres/backup_20260701_023000.sql.gz
2026-07-01T02:30:01Z [INFO] Backup succeeded: /opt/backups/postgres/backup_20260701_023000.sql.gz (48K)
2026-07-01T02:30:01Z [INFO] No old backups to prune
2026-07-01T02:30:01Z [INFO] Backup run complete
```

The script exits with a non-zero code on any failure, making it safe to use in cron with error alerting.

---

## 4. Restoring from a Backup

> [!IMPORTANT]
> Restoring overwrites all data in the target database. Stop or isolate the application before restoring to avoid write conflicts.

### Step 1 — Stop the application (optional but recommended)

```bash
docker compose -f compose/docker-compose.prod.yml stop app
```

### Step 2 — Decompress and pipe the dump into psql inside the postgres container

Replace `<backup_file>` with the full path to the `.sql.gz` file you want to restore.

```bash
# Identify the backup file
ls -lh /opt/backups/postgres/

# Restore (decompresses on the host, pipes into psql in the container)
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --filter "status=running" \
    --format "{{.Names}}" | grep -E '.*[-_]postgres[-_]?[0-9]*$' | head -n1)

gunzip --stdout /opt/backups/postgres/<backup_file> \
  | docker exec --interactive \
        --env PGPASSWORD="${POSTGRES_PASSWORD}" \
        "${POSTGRES_CONTAINER}" \
        psql \
            --username="${POSTGRES_USER}" \
            --dbname="${POSTGRES_DB}"
```

### Step 3 — Restart the application

```bash
docker compose -f compose/docker-compose.prod.yml start app
```

### Step 4 — Verify the restore

```bash
# Quick row count sanity check
docker exec --env PGPASSWORD="${POSTGRES_PASSWORD}" "${POSTGRES_CONTAINER}" \
    psql --username="${POSTGRES_USER}" --dbname="${POSTGRES_DB}" \
    --command="SELECT COUNT(*) FROM tasks;"
```

---

## 5. Backup Retention Policy

| Setting | Value |
|---------|-------|
| Retention period | **7 days** |
| Enforcement | `find … -mtime +7 -delete` run automatically at the end of each backup |
| Storage estimate | Depends on database size; for a small task DB, expect < 10 MB per file |

Backups older than 7 days are deleted automatically each time `backup.sh` runs. If the cron job stops running, old backups will accumulate until the job resumes.

---

## 6. Automated Backups via Cron

Add the following entry to the **root** crontab on the VPS (using `sudo crontab -e`) to run a backup every day at 02:00 UTC:

```cron
0 2 * * * cd /opt/app/fastAPI-redis-stack && set -a && . .env && set +a && bash scripts/backup.sh >> /var/log/taskapi-backup.log 2>&1
```

**Explanation of the crontab entry:**

| Part | Meaning |
|------|---------|
| `0 2 * * *` | Run at 02:00 UTC every day |
| `cd /opt/app/fastAPI-redis-stack` | Switch to the repo root (adjust path if different) |
| `set -a && . .env && set +a` | Source `.env` and export all variables (cron has no login environment) |
| `bash scripts/backup.sh` | Run the backup script |
| `>> /var/log/taskapi-backup.log 2>&1` | Append both stdout and stderr to the log file |

To verify the crontab was saved:

```bash
sudo crontab -l
```

---

## 7. Verifying a Backup Is Valid

### 7.1 — Check the file is non-empty and decompresses cleanly

```bash
# Inspect file size (should be > 0 bytes)
ls -lh /opt/backups/postgres/backup_YYYYMMDD_HHMMSS.sql.gz

# Test decompression integrity (exits non-zero if corrupt)
gunzip --test /opt/backups/postgres/backup_YYYYMMDD_HHMMSS.sql.gz && echo "OK: file decompresses cleanly"
```

### 7.2 — Inspect the SQL content

```bash
# Preview the first 30 lines of the dump without extracting
gunzip --stdout /opt/backups/postgres/backup_YYYYMMDD_HHMMSS.sql.gz | head -n 30
```

A valid dump begins with PostgreSQL header comments such as:

```sql
-- PostgreSQL database dump
-- Dumped from database version 16.x
```

### 7.3 — Review the backup log

```bash
tail -n 50 /var/log/taskapi-backup.log
```

Look for `[INFO] Backup succeeded` entries. Any `[ERROR]` lines indicate a failed run that requires investigation.

---

## 8. Troubleshooting

| Symptom | Likely cause | Resolution |
|---------|-------------|------------|
| `POSTGRES_USER is not set` | `.env` not sourced before running script | Run `source .env` first, or check cron `set -a && . .env && set +a` |
| `No running postgres container found` | Stack is not up | Run `docker compose -f compose/docker-compose.prod.yml up -d` |
| `pg_dump failed` | Wrong credentials or DB name | Verify `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` match the running container's environment |
| Backup file is 0 bytes | Pipe succeeded but pg_dump returned empty output | Check `docker logs <postgres-container>` for database errors |
| Cron job not running | Crontab not saved, or wrong path | Run `sudo crontab -l` to confirm; check `/var/log/syslog` for cron entries |
