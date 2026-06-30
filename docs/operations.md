# Day-to-Day Operations

This document provides quick reference commands for managing the production stack on the VPS. 

*All commands assume you are SSH'd into the VPS and are in the project root directory (`/opt/taskapi`).*

## Viewing Logs

View logs for all services (tail the last 50 lines and follow):
```bash
docker compose -f compose/docker-compose.prod.yml logs --tail=50 -f
```

View logs for a specific service:
```bash
docker compose -f compose/docker-compose.prod.yml logs --tail=50 -f app
docker compose -f compose/docker-compose.prod.yml logs --tail=50 -f postgres
```

## Restarting Services

Restart a single service (e.g., if the app hangs):
```bash
docker compose -f compose/docker-compose.prod.yml restart app
```

Restart the entire stack safely:
```bash
docker compose -f compose/docker-compose.prod.yml down
docker compose -f compose/docker-compose.prod.yml up -d
```

## Manual Deployment (Without CI/CD)

If GitHub Actions is unavailable, you can deploy manually:
```bash
git pull origin main
docker compose -f compose/docker-compose.prod.yml build app
docker compose -f compose/docker-compose.prod.yml up -d --remove-orphans
```

## Scaling App Replicas

> **Note**: Because this architecture relies on a single VPS with limited resources (e.g., t2.micro), scaling replicas heavily is not recommended. However, to run multiple worker containers:
```bash
docker compose -f compose/docker-compose.prod.yml up -d --scale app=3
```
*NGINX will automatically round-robin traffic to all available `app` containers via Docker's internal DNS resolution.*

## Connecting to PostgreSQL Directly

To open an interactive `psql` shell inside the running database container for debugging:
```bash
source .env
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.Names}}" | head -n1)
docker exec -it $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB
```

## Flushing the Redis Cache Manually

If you need to invalidate all rate limits and task caches immediately:
```bash
REDIS_CONTAINER=$(docker ps --filter "name=redis" --filter "status=running" --format "{{.Names}}" | head -n1)
docker exec -it $REDIS_CONTAINER redis-cli FLUSHALL
```

## Checking Disk Usage & Backups

Check how much space the Docker overlay filesystem is using:
```bash
docker system df
```

Check the size of your automated database backups:
```bash
ls -lh /opt/backups/postgres/
du -sh /opt/backups/postgres/
```
