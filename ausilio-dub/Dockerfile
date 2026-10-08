# Dub for Umbrel (experimental): pinned upstream build.
# Upstream has no releases and no official image, so pin the exact commit.
# Keep in sync with umbrel-app.yml version notes.
ARG DUB_COMMIT=41d76054bb1f0260e8bbae61cbc87a889116dbd1

FROM node:23.11.0-bookworm AS base
ARG DUB_COMMIT
ENV NODE_ENV=production \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH
RUN npm install -g pnpm@9.15.9 && \
    apt-get update && apt-get install -y --no-install-recommends git openssl ca-certificates python3 make g++ && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone https://github.com/dubinc/dub.git . && \
    git checkout ${DUB_COMMIT} && \
    rm -rf apps/web/vercel.json || true
# Install deps and pre-build internal packages (cached unless commit changes).
RUN pnpm i --frozen-lockfile || pnpm i --no-frozen-lockfile
RUN pnpm -r --filter "./packages/**" build || true
WORKDIR /app/apps/web
# Generate Prisma client at image build time (no DB connection needed).
RUN pnpm run prisma:generate || true
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
