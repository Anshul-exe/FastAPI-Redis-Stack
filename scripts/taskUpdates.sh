#!/bin/bash
# sending tasks every 10s, deletes old ones to prevent disk fill
BASE_URL="https://stack.anshulfml.me"
COUNTER=0

while true; do
  COUNTER=$((COUNTER + 1))

  # Create a task
  ID=$(curl -s -X POST "$BASE_URL/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"Auto task $COUNTER\",\"description\":\"Generated at $(date)\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

  echo "$(date) — Created task $ID"

  # Delete tasks older than ID-10 to keep DB small
  if [ "$COUNTER" -gt 10 ]; then
    OLD_ID=$((ID - 10))
    curl -s -X DELETE "$BASE_URL/tasks/$OLD_ID" >/dev/null
    echo "$(date) — Deleted task $OLD_ID"
  fi

  sleep 10
done
