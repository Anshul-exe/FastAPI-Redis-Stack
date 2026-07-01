#!/bin/bash
set -euo pipefail

cd /opt/taskapi
git pull origin main
docker compose -f compose/docker-compose.prod.yml pull app

# Capture the current app container ID before scaling
OLD_CONTAINER_ID=$(docker compose -f compose/docker-compose.prod.yml ps -q app)

echo "Scaling app to 2 replicas..."
docker compose -f compose/docker-compose.prod.yml up -d --scale app=2 --no-recreate

TIMEOUT=60
ELAPSED=0
SUCCESS=0

echo "Waiting for 2 app containers to be healthy..."
while [ $ELAPSED -lt $TIMEOUT ]; do
  # Parse JSON output to count healthy app containers
  HEALTHY_COUNT=$(docker compose -f compose/docker-compose.prod.yml ps --format json app | jq -r 'if type=="array" then .[] else . end | select(.Health == "healthy") | .ID' | wc -l || true)
  
  if [ "$HEALTHY_COUNT" -ge 2 ]; then
    SUCCESS=1
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ "$SUCCESS" -eq 0 ]; then
  echo "Error: Timeout reached waiting for 2 app containers to be healthy. Rolling back..."
  
  # Find the new container (the one that is not OLD_CONTAINER_ID)
  NEW_CONTAINER_ID=$(docker compose -f compose/docker-compose.prod.yml ps -q app | grep -v "$OLD_CONTAINER_ID" || true)
  
  if [ -n "$NEW_CONTAINER_ID" ]; then
    echo "Stopping and removing unhealthy new container ($NEW_CONTAINER_ID)..."
    docker stop "$NEW_CONTAINER_ID" || true
    docker rm "$NEW_CONTAINER_ID" || true
  fi
  
  echo "Confirming old container is still running..."
  if [ -n "$OLD_CONTAINER_ID" ]; then
    OLD_STATUS=$(docker inspect --format='{{.State.Status}}' "$OLD_CONTAINER_ID" || true)
    if [ "$OLD_STATUS" == "running" ]; then
      echo "Rollback successful. Old container ($OLD_CONTAINER_ID) is still running."
    else
      echo "Critical: Old container is NOT running! Status: $OLD_STATUS"
    fi
  else
    echo "Critical: No old container ID found during rollback."
  fi
  
  exit 1
fi

echo "Both replicas are healthy. Removing old container ($OLD_CONTAINER_ID)..."
if [ -n "$OLD_CONTAINER_ID" ]; then
  docker stop "$OLD_CONTAINER_ID"
  docker rm "$OLD_CONTAINER_ID"
fi

echo "Reloading NGINX to force DNS re-resolution..."
docker compose -f compose/docker-compose.prod.yml exec nginx nginx -s reload

echo "Reconciling state to 1 replica and bringing up other services..."
docker compose -f compose/docker-compose.prod.yml up -d --force-recreate nginx --remove-orphans
docker compose -f compose/docker-compose.prod.yml ps
