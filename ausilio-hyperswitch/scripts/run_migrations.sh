#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "=== Hyperswitch Migration Runner ========"
echo "========================================="

# Ensure diesel CLI is available
if ! command -v diesel >/dev/null 2>&1; then
  if [ -f /root/.cargo/bin/diesel ]; then
    export PATH="/root/.cargo/bin:${PATH}"
  fi
fi

if ! command -v diesel >/dev/null 2>&1; then
  echo "Installing dependencies and Diesel CLI..."
  apt-get update
  apt-get install -y --no-install-recommends curl xz-utils ca-certificates postgresql-client
  curl --proto '=https' --tlsv1.2 -LsSf https://github.com/diesel-rs/diesel/releases/download/v2.3.5/diesel_cli-installer.sh | bash
  export PATH="/root/.cargo/bin:${PATH}"
else
  # Ensure pg_isready is available if diesel was already cached
  if ! command -v pg_isready >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends postgresql-client ca-certificates
  fi
fi

echo "Diesel CLI ready: $(diesel --version)"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL at pg:5432..."
until pg_isready -h pg -p 5432 -U hyperswitch -d hyperswitch_db >/dev/null 2>&1; do
  echo "PostgreSQL is not ready yet, sleeping 2s..."
  sleep 2
done
echo "PostgreSQL is ready and accepting connections!"

# Ensure migrations exist in /app
if [ ! -f "/app/diesel.toml" ] || [ ! -d "/app/migrations" ]; then
  if [ -f "/migrations.tar.gz" ]; then
    echo "Extracting bundled migrations from /migrations.tar.gz into /app..."
    tar -xzf /migrations.tar.gz -C /app
  elif [ -f "/app/migrations.tar.gz" ]; then
    echo "Extracting bundled migrations from /app/migrations.tar.gz into /app..."
    tar -xzf /app/migrations.tar.gz -C /app
  fi
fi

if [ ! -f "/app/diesel.toml" ]; then
  echo "Error: diesel.toml not found in /app!"
  ls -la /app
  exit 1
fi

echo "Running migrations against database..."
cd /app
diesel migration run --database-url "${DATABASE_URL}" --migration-dir /app/migrations --config-file /app/diesel.toml

echo "========================================="
echo "=== Migrations completed successfully! =="
echo "========================================="
