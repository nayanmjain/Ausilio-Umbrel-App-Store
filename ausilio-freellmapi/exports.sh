# FreeLLMAPI for Umbrel: derive a stable 64-char hex ENCRYPTION_KEY.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
# Upstream requires ENCRYPTION_KEY to be 64 hex chars for AES-256-GCM key
# storage; hashing the per-app seed keeps it deterministic across restarts
# and upgrades so existing encrypted provider keys stay decryptable.
export APP_FREELLMAPI_ENCRYPTION_KEY="$(derive_entropy "ausilio-freellmapi-encryption-key" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"

mkdir -p "${APP_DATA_DIR}/data" 2>/dev/null || true
