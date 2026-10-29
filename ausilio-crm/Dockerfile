# CRM for Umbrel: Comp AI CRM, built from pinned upstream source.
# Upstream publishes no Docker image, so this package clones the `release`
# branch (pinned to CRM_COMMIT), installs Bun dependencies, generates the
# Prisma client, and builds the Next.js front end, NestJS API, and eve agent
# at image build time. Runtime applies Prisma migrations and starts the API,
# agent, and web app in one container alongside Postgres.
#
# Needs 4GB+ RAM for the first build. Both `oven/bun` and `postgres` are
# multi-arch, so this runs on x86_64 and arm64 Umbrel devices.
ARG CRM_COMMIT=c9473b82e3b4bfd5d0598bbdf7c1f36f3d2d68f0

FROM oven/bun:1.4
ENV NODE_ENV=production
WORKDIR /app

# git for the clone; openssl/ca-certificates for upstream fetch TLS;
# python3/make/g++ for native modules; curl for the runtime healthcheck;
# postgresql-client for pg_isready.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssl ca-certificates python3 make g++ curl postgresql-client \
    && rm -rf /var/lib/apt/lists/*

ARG CRM_COMMIT
RUN git clone https://github.com/trycompai/crm.git . \
    && git checkout ${CRM_COMMIT}

# Install workspace dependencies (frozen lockfile when it matches the tree).
RUN bun install --frozen-lockfile 2>/dev/null || bun install

# Generate the Prisma client (no database connection needed).
RUN bun run db:generate

# Build every app (Next.js, NestJS, agent). Build-time origins for the Next.js
# client; runtime origins come from the Compose environment.
ENV API_URL=http://localhost:3001 \
    APP_URL=http://localhost:3000 \
    NEXT_PUBLIC_API_URL=http://localhost:3001
RUN bun run build

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 2000
ENTRYPOINT ["/entrypoint.sh"]
