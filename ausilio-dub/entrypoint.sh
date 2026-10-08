#!/bin/sh
# Dub runtime entrypoint: push Prisma schema to local MySQL, then build once and start.
# First run takes 10-25 min on a 4GB+ server (Next.js production build).
set -e

cd /app/apps/web

echo "[dub] generating Prisma client..."
pnpm run prisma:generate || true

echo "[dub] pushing Prisma schema to local database..."
pnpm run prisma:push || echo "[dub] WARNING: prisma:push failed (db may not be ready yet or external keys missing)."

if [ ! -d ".next" ]; then
  echo "[dub] running first-time production build (this takes a while)..."
  pnpm run build || {
    echo "[dub] build failed; falling back to dev server on port 3000"
    exec pnpm run dev -- --port 3000
  }
fi

echo "[dub] starting web on port 3000..."
exec pnpm run start -- --port 3000
