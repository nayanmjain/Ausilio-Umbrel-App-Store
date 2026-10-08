# Ausilio Umbrel App Store

Community Umbrel app store (`id: ausilio`).

## Apps

| App | Version | Port | Category |
| --- | --- | --- | --- |
| AppFlowy (`ausilio-appflowy`) | 0.17.11 | 8081 | productivity |
| Cal.com DIY (`ausilio-cal-diy`) | 6.2.0 | 8083 | productivity |
| Listmonk (`ausilio-listmonk`) | 6.2.0 | 8084 | utilities |
| Documenso (`ausilio-documenso`) | 2.16.0 | 8085 | productivity |
| Paperclip (`ausilio-paperclip`) | 2026.916.1 | 8086 | ai |
| ERPNext (`ausilio-erpnext`) | 16.36.1 | 8087 | finance |
| Supabase (`ausilio-supabase`) | 2026.09.07 | 8088 | utilities |
| FreeLLMAPI (`ausilio-freellmapi`) | 0.13.6 | 8089 | ai |
| Shlink (`ausilio-shlink`) | 5.1.7 | 8090 | networking |
| Dub (`ausilio-dub`) | 2026.10.08 | 8091 | networking |
| Baserow (`ausilio-baserow`) | 2.4.0-1 | 8092 | productivity |

## Notes

- Cal.com (`ausilio-cal-diy`) uses the multi-arch `calcom/cal.com:v6.2.0` image and derives a
  32-char `CALENDSO_ENCRYPTION_KEY` in `exports.sh`. First-run signup is open by design (DIY).
- Listmonk (`ausilio-listmonk`) uses multi-arch `listmonk/listmonk:v6.2.0`.
- AppFlowy Minio was bumped to `RELEASE.2025-09-07T16-13-09Z` (bundles curl/mc, required for healthcheck).
  `MINIO_ROOT_USER`/`ROOT_PASSWORD` intentionally reuse `APP_PASSWORD` for backward compat with
  existing volumes; changing them would orphan existing buckets.
- Documenso internal URL is `http://web:3000` (container DNS, not localhost). Uploads persist in Postgres.
- ERPNext needs 4GB+ RAM (12 services). Category is `finance` to match store taxonomy.
  First install builds the site via `create-site` (10-20 min on a Pi); runtime services wait
  for it, so the app only becomes reachable once setup finishes. Data lives under `data/`
  (`sites`, `logs`, `db`, `redis-queue`); remove the app's data dir before reinstalling after
  a failed install, or a half-created site will be skipped as "already exists".
- Paperclip has no default credentials by design: the first signup claims instance ownership.
  Bring your own model provider keys; usage may incur costs.
- FreeLLMAPI (`ausilio-freellmapi`) serves its dashboard and the unified
  OpenAI-compatible API on port 8089 (`/v1`, plus `/v1/messages`, `/v1beta`,
  Ollama emulation, and `/mcp`). `exports.sh` derives a deterministic 64-char
  hex `ENCRYPTION_KEY` from the Umbrel seed so encrypted provider keys survive
  restarts/upgrades. Data (SQLite) persists in `${APP_DATA_DIR}/data`.
  First-run setup is open by design: create the first dashboard account in the
  browser (a one-time setup code is printed in the app logs while no account
  exists). Bring your own free-tier provider keys; the router stays within
  each provider's free cap via per-key rate tracking.
- Supabase (`ausilio-supabase`) serves Studio and all APIs through one Envoy gateway on
  port 8088 (Studio at `/`, APIs under `/auth/v1`, `/rest/v1`, `/realtime/v1`,
  `/storage/v1`, `/functions/v1`). Envoy configs and Postgres init SQL are snapshotted
  from upstream `supabase/supabase:docker` and provisioned into `${APP_DATA_DIR}` by
  `exports.sh`, which also derives the HS256 `JWT_SECRET` plus anon/service_role API
  keys deterministically. The Postgres `db-config` mount must stay a named volume:
  Docker seeds it with the image's baked `/etc/postgresql-custom` content
  (`read-replica.conf`, `conf.d`), which `postgresql.conf` actively includes; an
  empty bind mount hides those files and Postgres fatals on startup. If a previous
  install failed mid-init, delete the half-initialized database dir before
  reinstalling (`sudo rm -rf ~/umbrel/app-data/ausilio-supabase/db`), or the
  entrypoint will skip the Supabase init scripts as "already initialized". Dashboard login is `admin` / `${APP_PASSWORD}` (basic auth);
  anon/service keys are shown in Studio API settings. Email confirmation is
  auto-approved (no SMTP on Umbrel); phone auth is disabled. Supavisor is omitted
  (services connect to Postgres directly). Needs 2GB+ RAM (10 services).
- Shlink (`ausilio-shlink`) runs the `shlinkio/shlink:5.1.7` backend (multi-arch)
  plus Postgres, fully offline. `exports.sh` derives a deterministic UUID-format
  `INITIAL_API_KEY` (Shlink only honors it when no keys exist, so it must be
  stable); it is also persisted to `${APP_DATA_DIR}/exports.env` for retrieval.
  The Umbrel port (8090) is part of `DEFAULT_DOMAIN`, so short URLs look like
  `http://<server>:8090/<code>`. Manage it from https://app.shlink.io (static,
  runs in your browser) by adding a server with your Umbrel URL + API key.
  Geo-tracking stays off (`SKIP_INITIAL_GEOLITE_DOWNLOAD=true`, no license key).
- Dub (`ausilio-dub`) is EXPERIMENTAL: upstream has no releases and no official
  Docker image, so this builds pinned source (`41d7605`, 2026-10-08) on first
  install (10-25 min, needs 4GB+ RAM) with local MySQL + PlanetScale simulator
  (`ps-http-sim`) + Mailhog. Upstream requires external SaaS even for local dev,
  so without your own `UPSTASH_REDIS_REST_URL/TOKEN`, `QSTASH_TOKEN` + signing
  keys, `TINYBIRD_API_KEY/URL`, and a login provider (`GITHUB_CLIENT_ID/SECRET`
  or SMTP magic links), redirects/analytics stay degraded. Mock Stripe keys keep
  workspace routes from 500ing locally. For one-click offline shortening, use
  Shlink instead.

- Baserow (`ausilio-baserow`) runs the official all-in-one `baserow/baserow:2.4.0`
  image (embedded Postgres + Redis behind Caddy on internal port 80).
  `BASEROW_PUBLIC_URL` points at the Umbrel host port (8092) and
  `BASEROW_CADDY_ADDRESSES=:80` keeps it on plain HTTP behind Umbrel's
  `app_proxy`. Secrets (Django `SECRET_KEY`, DB/Redis passwords) are
  auto-generated into `/baserow/data`, so all state persists in `data/`.
  `BASEROW_RUN_MINIMAL=yes` with one worker keeps RAM down. First browser
  signup claims instance ownership; no SMTP is configured. `exports.sh`
  registers the device hostname, app domain, and LAN IPs in
  `BASEROW_EXTRA_PUBLIC_URLS`/`BASEROW_EXTRA_ALLOWED_HOSTS`, otherwise Baserow
  shows "Site not found" when the browser URL host differs from
  `BASEROW_PUBLIC_URL`. Needs 2GB+ RAM.
  First boot applies migrations and can take several minutes.

## Validation

CI (`.github/workflows/validate.yml`) checks manifest shape, category allow-list, no obsolete
compose `version:`, no arch-specific tags, and `docker compose config` per app.
