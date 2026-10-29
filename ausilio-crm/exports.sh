# CRM for Umbrel: derive stable, per-install secrets.
# Sourced by Umbrel on install/start. Must stay idempotent and fast so that
# restarts and upgrades do not rotate secrets (which would invalidate sessions
# and any encrypted rows). All values are derived deterministically from the
# per-app Umbrel seed via derive_entropy.
export APP_CRM_BETTER_AUTH_SECRET="$(derive_entropy "ausilio-crm-better-auth-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
export APP_CRM_AGENT_BRIDGE_SECRET="$(derive_entropy "ausilio-crm-agent-bridge-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
export APP_CRM_CRON_SECRET="$(derive_entropy "ausilio-crm-cron-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"

mkdir -p "${APP_DATA_DIR}/db_data" 2>/dev/null || true
