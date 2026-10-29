#!/bin/sh
# CRM for Umbrel runtime entrypoint.
# Waits for Postgres, applies Prisma migrations, then starts the NestJS API
# (port 3001), the eve research agent (port 2000), and the Next.js web app
# (port 3000, the container's foreground process that Umbrel proxies).
set -e

cd /app

echo "[crm] waiting for Postgres at db:5432..."
for i in $(seq 1 120); do
  if pg_isready -h db -U postgres -d crm >/dev/null 2>&1; then
    echo "[crm] Postgres is ready."
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "[crm] ERROR: Postgres did not become ready." >&2
    exit 1
  fi
  sleep 2
done

echo "[crm] applying Prisma migrations..."
bun run db:deploy || {
  echo "[crm] WARNING: prisma migrate deploy failed; continuing anyway." >&2
}

echo "[crm] starting API on port 3001..."
( cd /app/apps/api && PORT=3001 bun dist/main.js ) &
API_PID=$!

echo "[crm] starting agent on port 2000..."
( cd /app/apps/agent && AGENT_PORT=2000 bunx eve start --port 2000 ) &
AGENT_PID=$!

trap 'kill "$API_PID" "$AGENT_PID" 2>/dev/null || true' TERM INT

# Give API and agent a moment to bind before the web app starts.
sleep 5

echo "[crm] starting web app on port 3000..."
cd /app/apps/app
PORT=3000 bun run start

kill "$API_PID" "$AGENT_PID" 2>/dev/null || true
wait 2>/dev/null || true
