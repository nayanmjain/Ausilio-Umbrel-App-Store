# Dub for Umbrel (experimental): derive stable secrets.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
# Secrets are deterministic per Umbrel seed (derive_entropy) so restarts and
# upgrades keep the same NextAuth/encryption/cron secrets (rotating them
# would invalidate sessions and undecryptable rows).
export APP_DUB_NEXTAUTH_SECRET="$(derive_entropy "ausilio-dub-nextauth-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
export APP_DUB_ENCRYPTION_KEY="$(derive_entropy "ausilio-dub-encryption-key" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
export APP_DUB_CRON_SECRET="$(derive_entropy "ausilio-dub-cron-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"

mkdir -p "${APP_DATA_DIR}/mysql_data" "${APP_DATA_DIR}/mailhog_data" 2>/dev/null || true
