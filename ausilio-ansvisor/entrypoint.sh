#!/bin/sh
# Ansvisor runtime entrypoint for Umbrel.
# Starts the backend server on port 80 and the Next.js web dashboard on port 3000.
set -e

echo "[ansvisor] starting Express API backend on port 80..."
cd /app/server
pm2 start src/server.js --name ansvisor-server

echo "[ansvisor] starting Next.js web application on port 3000..."
cd /app/web
PORT=3000 npm run start
