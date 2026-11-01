# Ansvisor for Umbrel: built from pinned upstream source.
# Upstream does not publish public Docker images, so we build from the pinned
# v0.3.0 commit (de1bb6ca7f751808d077e7eb7975bdbe6dfed654).
# This single container runs both the Express backend API (port 80) and
# the Next.js web application (port 3000) concurrently via PM2 / backgrounding.
ARG ANSVISOR_COMMIT=de1bb6ca7f751808d077e7eb7975bdbe6dfed654

FROM node:20-bookworm AS base
ARG ANSVISOR_COMMIT
ENV NODE_ENV=production

RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssl ca-certificates curl python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/ansvisor/ansvisor.git . \
    && git checkout ${ANSVISOR_COMMIT}

# Install global PM2 to manage both processes
RUN npm install -g pm2

# Install backend dependencies
WORKDIR /app/server
RUN npm install --production

# Install frontend dependencies and build Next.js
WORKDIR /app/web
RUN yarn install --frozen-lockfile || npm install
RUN npm run build

WORKDIR /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 80
ENTRYPOINT ["/entrypoint.sh"]
