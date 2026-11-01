# Ansvisor for Umbrel: derive stable secrets.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
APP_ANSVISOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export APP_ANSVISOR_DIR

# Secrets are deterministic per Umbrel seed (derive_entropy) so restarts and
# upgrades keep the same cron/encryption secrets (rotating them would break
# signed internal calls and any encrypted data).
export APP_ANSIVISOR_CRON_SECRET="$(derive_entropy "ausilio-ansvisor-cron-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
export APP_ANSIVISOR_ENCRYPTION_KEY="$(derive_entropy "ausilio-ansvisor-encryption-key" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-44 | tr -d '\n' | openssl base64 -A | cut -c1-44)"

mkdir -p "${APP_DATA_DIR}" 2>/dev/null || true
cp -f "${APP_ANSVISOR_DIR}/Dockerfile" "${APP_DATA_DIR}/Dockerfile" 2>/dev/null || true
cp -f "${APP_ANSVISOR_DIR}/entrypoint.sh" "${APP_DATA_DIR}/entrypoint.sh" 2>/dev/null || true

# Persist derivable secrets for easy retrieval.
printf 'APP_ANSIVISOR_CRON_SECRET=%s\n' "${APP_ANSIVISOR_CRON_SECRET}" > "${APP_DATA_DIR}/exports.env" 2>/dev/null || true
printf 'APP_ANSIVISOR_ENCRYPTION_KEY=%s\n' "${APP_ANSIVISOR_ENCRYPTION_KEY}" >> "${APP_DATA_DIR}/exports.env" 2>/dev/null || true
