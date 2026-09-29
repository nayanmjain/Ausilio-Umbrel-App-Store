# Ausilio Umbrel App Store

Community Umbrel app store (`id: ausilio`).

## Apps

| App | Version | Port | Category |
| --- | --- | --- | --- |
| AppFlowy (`ausilio-appflowy`) | 0.17.11 | 8081 | productivity |
| Cal.com DIY (`ausilio-cal-diy`) | 6.2.0 | 8083 | productivity |
| Listmonk (`ausilio-listmonk`) | 6.2.0 | 8084 | utilities |
| Documenso (`ausilio-documenso`) | 2.16.0 | 8085 | productivity |
| Paperclip (`ausilio-paperclip`) | 2026.722.0 | 8086 | ai |
| ERPNext (`ausilio-erpnext`) | 16.32.1 | 8087 | finance |

## Notes

- Cal.com (`ausilio-cal-diy`) uses the multi-arch `calcom/cal.com:v6.2.0` image and derives a
  32-char `CALENDSO_ENCRYPTION_KEY` in `exports.sh`. First-run signup is open by design (DIY).
- Listmonk (`ausilio-listmonk`) uses multi-arch `listmonk/listmonk:v6.2.0`.
- AppFlowy Minio was bumped to `RELEASE.2025-09-07T16-13-09Z` (bundles curl/mc, required for healthcheck).
  `MINIO_ROOT_USER`/`ROOT_PASSWORD` intentionally reuse `APP_PASSWORD` for backward compat with
  existing volumes; changing them would orphan existing buckets.
- Documenso internal URL is `http://web:3000` (container DNS, not localhost). Uploads persist in Postgres.
- ERPNext needs 4GB+ RAM (12 services). Category is `finance` to match store taxonomy.
- Paperclip has no default credentials by design: the first signup claims instance ownership.
  Bring your own model provider keys; usage may incur costs.

## Validation

CI (`.github/workflows/validate.yml`) checks manifest shape, category allow-list, no obsolete
compose `version:`, no arch-specific tags, and `docker compose config` per app.
