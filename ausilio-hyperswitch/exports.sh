#!/usr/bin/env bash
# Hyperswitch for Umbrel: derive secrets, provision config & migrations.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.

APP_HYPERSWITCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export APP_HYPERSWITCH_DIR

export APP_HYPERSWITCH_DATA_ROOT="${APP_DATA_ROOT:-${APP_DATA_DIR:-${APP_HYPERSWITCH_DIR}/data}}"

# Load optional user overrides if present
if [ -f "${APP_HYPERSWITCH_DATA_ROOT}/config.env" ]; then
  # shellcheck disable=SC1090
  . "${APP_HYPERSWITCH_DATA_ROOT}/config.env"
fi

# Derive deterministic database password from Umbrel seed
if [ -z "${APP_HYPERSWITCH_DB_PASSWORD:-}" ]; then
  if command -v derive_entropy >/dev/null 2>&1; then
    APP_HYPERSWITCH_DB_PASSWORD="$(derive_entropy "ausilio-hyperswitch-db-password" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"
  else
    APP_HYPERSWITCH_DB_PASSWORD="$(openssl rand -hex 16)"
  fi
fi
export APP_HYPERSWITCH_DB_PASSWORD

# Derive deterministic admin password meeting Hyperswitch complexity requirements
# (at least 12 chars, containing uppercase, lowercase, digit, and special characters)
if [ -z "${APP_HYPERSWITCH_ADMIN_PASSWORD:-}" ]; then
  if command -v derive_entropy >/dev/null 2>&1; then
    _admin_seed="$(derive_entropy "ausilio-hyperswitch-admin-pw" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-16)"
    APP_HYPERSWITCH_ADMIN_PASSWORD="Hs#${_admin_seed}9!"
  else
    APP_HYPERSWITCH_ADMIN_PASSWORD="Hyperswitch@123"
  fi
fi
export APP_HYPERSWITCH_ADMIN_PASSWORD

export APP_HYPERSWITCH_ADMIN_EMAIL="${APP_HYPERSWITCH_ADMIN_EMAIL:-admin@hyperswitch.local}"

# Create persistent storage directories
mkdir -p \
  "${APP_HYPERSWITCH_DATA_ROOT}/pgdata" \
  "${APP_HYPERSWITCH_DATA_ROOT}/redisdata" \
  "${APP_HYPERSWITCH_DATA_ROOT}/config" \
  "${APP_HYPERSWITCH_DATA_ROOT}/scripts" \
  "${APP_HYPERSWITCH_DATA_ROOT}/gateway" \
  "${APP_HYPERSWITCH_DATA_ROOT}/migrations" \
  "${APP_HYPERSWITCH_DATA_ROOT}/bin" 2>/dev/null || true

# Provision gateway configuration
if [ -f "${APP_HYPERSWITCH_DIR}/gateway/nginx.conf" ]; then
  cp -f "${APP_HYPERSWITCH_DIR}/gateway/nginx.conf" "${APP_HYPERSWITCH_DATA_ROOT}/gateway/nginx.conf" 2>/dev/null || true
fi

# Provision config files
for _cfg in dashboard.toml dashboard_theme.json superposition_seed.toml; do
  if [ -f "${APP_HYPERSWITCH_DIR}/config/${_cfg}" ]; then
    cp -f "${APP_HYPERSWITCH_DIR}/config/${_cfg}" "${APP_HYPERSWITCH_DATA_ROOT}/config/${_cfg}" 2>/dev/null || true
  fi
done

# Provision docker_compose.toml with substituted db password
if [ -f "${APP_HYPERSWITCH_DIR}/config/docker_compose.toml" ]; then
  sed "s/password = \"db_pass\"/password = \"${APP_HYPERSWITCH_DB_PASSWORD}\"/g" \
    "${APP_HYPERSWITCH_DIR}/config/docker_compose.toml" > "${APP_HYPERSWITCH_DATA_ROOT}/config/docker_compose.toml" 2>/dev/null || true
fi

# Provision scripts
for _script in seed_superposition.sh create_default_user.sh; do
  if [ -f "${APP_HYPERSWITCH_DIR}/scripts/${_script}" ]; then
    cp -f "${APP_HYPERSWITCH_DIR}/scripts/${_script}" "${APP_HYPERSWITCH_DATA_ROOT}/scripts/${_script}" 2>/dev/null || true
    chmod 0755 "${APP_HYPERSWITCH_DATA_ROOT}/scripts/${_script}" 2>/dev/null || true
  fi
done

# Extract bundled schema migrations if not already present
if [ ! -f "${APP_HYPERSWITCH_DATA_ROOT}/migrations/diesel.toml" ] && [ -f "${APP_HYPERSWITCH_DIR}/migrations.tar.gz" ]; then
  tar -xzf "${APP_HYPERSWITCH_DIR}/migrations.tar.gz" -C "${APP_HYPERSWITCH_DATA_ROOT}/migrations" 2>/dev/null || true
fi

# Persist environment info for user reference and debugging
cat > "${APP_HYPERSWITCH_DATA_ROOT}/exports.env" <<EOF
APP_HYPERSWITCH_PORT=8097
APP_HYPERSWITCH_ADMIN_EMAIL=${APP_HYPERSWITCH_ADMIN_EMAIL}
APP_HYPERSWITCH_ADMIN_PASSWORD=${APP_HYPERSWITCH_ADMIN_PASSWORD}
APP_HYPERSWITCH_DB_USER=hyperswitch
APP_HYPERSWITCH_DB_NAME=hyperswitch_db
APP_HYPERSWITCH_DB_PASSWORD=${APP_HYPERSWITCH_DB_PASSWORD}
EOF
chmod 0600 "${APP_HYPERSWITCH_DATA_ROOT}/exports.env" 2>/dev/null || true
