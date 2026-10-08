# Shlink for Umbrel: derive a stable API key and persist it for display.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
# Shlink only creates INITIAL_API_KEY once (when no keys exist); changing it
# later does not rotate the key, so it must be deterministic across restarts
# and upgrades. Format as UUID (8-4-4-4-12) from the per-app seed.
_SHLINK_HEX="$(derive_entropy "ausilio-shlink-api-key" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"
export APP_SHLINK_API_KEY="$(printf '%s' "${_SHLINK_HEX}" | sed -e 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')"
unset _SHLINK_HEX 2>/dev/null || true

mkdir -p "${APP_DATA_DIR}" 2>/dev/null || true
# Persist for easy retrieval (grep APP_SHLINK_API_KEY exports.env).
printf 'APP_SHLINK_API_KEY=%s\n' "${APP_SHLINK_API_KEY}" > "${APP_DATA_DIR}/exports.env" 2>/dev/null || true
