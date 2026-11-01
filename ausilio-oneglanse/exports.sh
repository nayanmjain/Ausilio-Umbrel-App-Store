# OneGlanse for Umbrel: derive stable secrets, provision database init files,
# and export runtime variables.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
#
# User-editable settings live in a sibling config.env next to this file:
#   ~/umbrel/app-data/ausilio-oneglanse/config.env
# That file is not touched by app updates. It uses shell syntax, e.g.
#   APP_ONEGLANSE_OPENAI_API_KEY=sk-...
#   APP_ONEGLANSE_THORDATA_PROXY_API_URL=https://...

ONEGLANSE_APP_DIR="${APP_DATA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"

if [ -f "${ONEGLANSE_APP_DIR}/config.env" ]; then
  # shellcheck disable=SC1090
  . "${ONEGLANSE_APP_DIR}/config.env"
fi

# Normalize variable names from config.env (support both native and prefixed)
for _og_name in \
  OPENAI_API_KEY ANTHROPIC_API_KEY OPENAI_BASE_URL ANALYSIS_OPENAI_MODEL \
  ANALYSIS_OPENAI_API THORDATA_PROXY_API_URL PROXY_SCHEME GOOGLE_CLIENT_ID \
  GOOGLE_CLIENT_SECRET DEBUG_ENABLED CAMOUFOX_HEADLESS_MODE \
  ANALYSIS_LLM_PROVIDER APP_URL
do
  eval "_og_val=\"\${${_og_name}:-\${APP_ONEGLANSE_${_og_name}:-}}\""
  if [ -n "${_og_val}" ]; then
    eval "export APP_ONEGLANSE_${_og_name}=\"\${_og_val}\""
  fi
done
unset _og_name _og_val

# Persistent data root. Newer umbrelOS may relocate it away from the app dir.
export APP_ONEGLANSE_DATA_ROOT="${APP_DATA_ROOT:-${ONEGLANSE_APP_DIR}/data}"

# Public origin used by Better Auth for cookies and origin checks.
export APP_ONEGLANSE_APP_URL="${APP_ONEGLANSE_APP_URL:-http://${DEVICE_DOMAIN_NAME:-umbrel.local}:8095}"

# --- Secrets (deterministic per Umbrel seed, stable across restarts/upgrades) ---
export APP_ONEGLANSE_BETTER_AUTH_SECRET="$(derive_entropy "ausilio-oneglanse-better-auth-secret" | cut -c1-64)"
export APP_ONEGLANSE_INTERNAL_CRON_SECRET="$(derive_entropy "ausilio-oneglanse-internal-cron-secret" | cut -c1-64)"
export APP_ONEGLANSE_AGENT_AUTH_UPLOAD_TOKEN="$(derive_entropy "ausilio-oneglanse-agent-auth-upload-token" | cut -c1-64)"
export APP_ONEGLANSE_DB_PASSWORD="$(derive_entropy "ausilio-oneglanse-db-password" | cut -c1-32)"
export APP_ONEGLANSE_REDIS_PASSWORD="$(derive_entropy "ausilio-oneglanse-redis-password" | cut -c1-32)"
export APP_ONEGLANSE_CLICKHOUSE_PASSWORD="$(derive_entropy "ausilio-oneglanse-clickhouse-password" | cut -c1-32)"

# --- Data directories ---
mkdir -p \
  "${APP_ONEGLANSE_DATA_ROOT}/db/data" \
  "${APP_ONEGLANSE_DATA_ROOT}/db-init" \
  "${APP_ONEGLANSE_DATA_ROOT}/clickhouse/data" \
  "${APP_ONEGLANSE_DATA_ROOT}/clickhouse-init" \
  "${APP_ONEGLANSE_DATA_ROOT}/redis/data" \
  "${APP_ONEGLANSE_DATA_ROOT}/storage" 2>/dev/null || true

# Bind-mounted service data dirs are created by this script, not by the image,
# so the containers (which run as non-root users) need write access. Do not
# recurse: children are created by each service with the right ownership.
chmod 0777 \
  "${APP_ONEGLANSE_DATA_ROOT}/clickhouse/data" \
  "${APP_ONEGLANSE_DATA_ROOT}/redis/data" \
  "${APP_ONEGLANSE_DATA_ROOT}/storage" 2>/dev/null || true
chmod 0755 "${APP_ONEGLANSE_DATA_ROOT}/db-init" "${APP_ONEGLANSE_DATA_ROOT}/clickhouse-init" 2>/dev/null || true

# --- Postgres init (pg_cron + http for schedules) ---
cat > "${APP_ONEGLANSE_DATA_ROOT}/db-init/00-init.sql" <<'ONEGLANSE_EOF_PG_INIT'
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "http";

DO $$
DECLARE
	app_role text := current_user;
	http_fn record;
BEGIN
	-- Limit pg_cron schema usage to the application role only.
	REVOKE USAGE ON SCHEMA cron FROM PUBLIC;
	EXECUTE format('GRANT USAGE ON SCHEMA cron TO %I', app_role);

	-- Limit http extension function execution to the application role only.
	FOR http_fn IN
		SELECT
			n.nspname AS schema_name,
			p.proname AS function_name,
			pg_get_function_identity_arguments(p.oid) AS function_args
		FROM pg_proc p
		JOIN pg_namespace n ON n.oid = p.pronamespace
		JOIN pg_depend d ON d.objid = p.oid AND d.deptype = 'e'
		JOIN pg_extension e ON e.oid = d.refobjid
		WHERE e.extname = 'http'
	LOOP
		EXECUTE format(
			'REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC',
			http_fn.schema_name,
			http_fn.function_name,
			http_fn.function_args
		);
		EXECUTE format(
			'GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I',
			http_fn.schema_name,
			http_fn.function_name,
			http_fn.function_args,
			app_role
		);
	END LOOP;
END;
$$;
ONEGLANSE_EOF_PG_INIT

# --- ClickHouse init (prompts, responses, citations, analysis) ---
cat > "${APP_ONEGLANSE_DATA_ROOT}/clickhouse-init/schema.sql" <<'ONEGLANSE_EOF_CH_SCHEMA'
CREATE DATABASE IF NOT EXISTS analytics;

CREATE TABLE IF NOT EXISTS analytics.user_prompts (
    id String,
    user_id String,
    workspace_id String,
    prompt String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree()
PRIMARY KEY (workspace_id, prompt)
ORDER BY (workspace_id, prompt, created_at);

CREATE TABLE IF NOT EXISTS analytics.prompt_responses (
    id String,
    prompt_id String,
    prompt String,
    user_id String,
    workspace_id String,
    model String,
    model_provider LowCardinality(String),
    response String,
    sources Array(Tuple(
        title String,
        cited_text String,
        url String,
        domain Nullable(String),
        favicon Nullable(String)
    )),
    is_analysed Bool DEFAULT false,
    prompt_run_at DateTime,
    created_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree()
PARTITION BY toYYYYMM(prompt_run_at)
ORDER BY (workspace_id, prompt_run_at, model_provider, prompt_id);

CREATE TABLE IF NOT EXISTS analytics.prompt_analysis (
    id String,
    prompt_id String,
    workspace_id String,
    user_id String,
    model_provider LowCardinality(String),
    brand_analysis String DEFAULT '',
    prompt_run_at DateTime,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(prompt_run_at)
ORDER BY (
    workspace_id,
    prompt_id,
    prompt_run_at,
    model_provider
);

ALTER TABLE analytics.prompt_analysis ADD COLUMN IF NOT EXISTS prompt String DEFAULT '';
ONEGLANSE_EOF_CH_SCHEMA

# --- Persist derived secrets for the operator ---
ONEGLANSE_EXPORTS_ENV="${ONEGLANSE_APP_DIR}/exports.env"
{
  printf 'APP_ONEGLANSE_AGENT_AUTH_UPLOAD_TOKEN=%s\n' "${APP_ONEGLANSE_AGENT_AUTH_UPLOAD_TOKEN}"
  printf 'APP_ONEGLANSE_DB_PASSWORD=%s\n' "${APP_ONEGLANSE_DB_PASSWORD}"
  printf 'APP_ONEGLANSE_REDIS_PASSWORD=%s\n' "${APP_ONEGLANSE_REDIS_PASSWORD}"
  printf 'APP_ONEGLANSE_CLICKHOUSE_PASSWORD=%s\n' "${APP_ONEGLANSE_CLICKHOUSE_PASSWORD}"
  printf 'APP_ONEGLANSE_DATA_ROOT=%s\n' "${APP_ONEGLANSE_DATA_ROOT}"
} > "${ONEGLANSE_EXPORTS_ENV}" 2>/dev/null || true
chmod 600 "${ONEGLANSE_EXPORTS_ENV}" 2>/dev/null || true
