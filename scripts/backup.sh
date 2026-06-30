#!/usr/bin/env bash
# =============================================================================
# scripts/backup.sh — PostgreSQL backup for the Task Management API
#
# Usage:
#   bash scripts/backup.sh          (from repo root on the VPS)
#
# Prerequisites:
#   - Docker and Docker Compose must be running
#   - POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB must be set in environment
#     (source /path/to/.env or export them before calling this script)
#   - The postgres service container must be running
#
# Output:
#   Compressed dump:  /opt/backups/postgres/backup_YYYYMMDD_HHMMSS.sql.gz
#   Log file:         /var/log/taskapi-backup.log
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BACKUP_DIR="/opt/backups/postgres"
LOG_FILE="/var/log/taskapi-backup.log"
RETENTION_DAYS=7

# Resolve the postgres container name from the running compose project.
# Docker Compose names containers as <project>-<service>-<replica>.
# We match the service name "postgres" so this works regardless of the
# directory/project name the operator used.
POSTGRES_CONTAINER="$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.Names}}" | grep -E '.*[-_]postgres[-_]?[0-9]*$' | head -n1)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [$level] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR" "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${POSTGRES_USER:?Environment variable POSTGRES_USER is not set}"
: "${POSTGRES_PASSWORD:?Environment variable POSTGRES_PASSWORD is not set}"
: "${POSTGRES_DB:?Environment variable POSTGRES_DB is not set}"

# ---------------------------------------------------------------------------
# Validate postgres container is reachable
# ---------------------------------------------------------------------------
if [[ -z "$POSTGRES_CONTAINER" ]]; then
    die "No running postgres container found. Is the compose stack up?"
fi

log "INFO" "Using container: $POSTGRES_CONTAINER"

# ---------------------------------------------------------------------------
# Ensure backup directory exists
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR" || die "Failed to create backup directory: $BACKUP_DIR"

# ---------------------------------------------------------------------------
# Build output filename
# ---------------------------------------------------------------------------
TIMESTAMP="$(date -u '+%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.sql.gz"

# ---------------------------------------------------------------------------
# Run pg_dump inside the container, stream output through gzip on the host
# ---------------------------------------------------------------------------
log "INFO" "Starting backup of database '${POSTGRES_DB}' → ${BACKUP_FILE}"

if docker exec \
        --env PGPASSWORD="${POSTGRES_PASSWORD}" \
        "${POSTGRES_CONTAINER}" \
        pg_dump \
            --username="${POSTGRES_USER}" \
            --dbname="${POSTGRES_DB}" \
            --no-password \
            --format=plain \
    | gzip > "${BACKUP_FILE}"; then

    BACKUP_SIZE="$(du -sh "${BACKUP_FILE}" | cut -f1)"
    log "INFO" "Backup succeeded: ${BACKUP_FILE} (${BACKUP_SIZE})"
else
    # Remove incomplete/empty file on failure
    rm -f "${BACKUP_FILE}"
    die "pg_dump failed. Partial backup removed."
fi

# ---------------------------------------------------------------------------
# Verify the backup file is non-empty
# ---------------------------------------------------------------------------
if [[ ! -s "${BACKUP_FILE}" ]]; then
    rm -f "${BACKUP_FILE}"
    die "Backup file is empty after dump. Removed."
fi

# ---------------------------------------------------------------------------
# Prune backups older than RETENTION_DAYS
# ---------------------------------------------------------------------------
log "INFO" "Pruning backups older than ${RETENTION_DAYS} days from ${BACKUP_DIR}"

PRUNED="$(find "${BACKUP_DIR}" -maxdepth 1 -name "backup_*.sql.gz" \
    -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)"

if [[ "$PRUNED" -gt 0 ]]; then
    log "INFO" "Pruned ${PRUNED} old backup(s)"
else
    log "INFO" "No old backups to prune"
fi

log "INFO" "Backup run complete"
