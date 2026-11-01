# Elmo for Umbrel: derive stable secrets and export runtime variables.
# Sourced by Umbrel on install/start. Must stay idempotent and fast so that
# restarts and upgrades do not rotate secrets (which would invalidate sessions
# and make stored provider credentials unreadable).
#
# User-editable settings live in a sibling config.env next to this file:
#   ~/umbrel/app-data/ausilio-elmo/config.env
# That file is not touched by app updates. It uses shell syntax and accepts
# either the upstream names (OPENROUTER_API_KEY=...) or an APP_ELMO_ prefix
# (APP_ELMO_OPENROUTER_API_KEY=...). See config.env.example.

ELMO_APP_DIR="${APP_DATA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
ELMO_CONFIG_ENV="${ELMO_APP_DIR}/config.env"

if [ -f "${ELMO_CONFIG_ENV}" ]; then
  # shellcheck disable=SC1090
  . "${ELMO_CONFIG_ENV}"
fi

# Normalize variable names from config.env (supports both upstream and APP_ELMO_ prefixes)
for _elmo_name in \
  BRIGHTDATA_API_TOKEN CLORO_API_KEY SEARCHAPI_API_KEY OLOSTEP_API_KEY \
  OXYLABS_USERNAME OXYLABS_PASSWORD DATAFORSEO_LOGIN DATAFORSEO_PASSWORD \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY MISTRAL_API_KEY \
  TYPESAFE_API_KEY JINA_API_KEY REPROCESS_DAYS ONBOARDING_LLM_TARGET \
  RUNS_PER_PROMPT DEFAULT_DELAY_HOURS SCRAPE_TARGETS APP_URL DISABLE_TELEMETRY \
  ELMO_ENCRYPTION_KEY_OLD
do
  eval "_elmo_val=\"\${${_elmo_name}:-\${APP_ELMO_${_elmo_name}:-}}\""
  if [ -n "${_elmo_val}" ]; then
    eval "export APP_ELMO_${_elmo_name}=\"\${_elmo_val}\""
  fi
done
unset _elmo_name _elmo_val

# --- Secrets (deterministic per Umbrel seed, stable across restarts/upgrades) ---
export APP_ELMO_DB_PASSWORD="$(derive_entropy "ausilio-elmo-db-password" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"
export APP_ELMO_BETTER_AUTH_SECRET="$(derive_entropy "ausilio-elmo-better-auth-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
# Elmo requires standard base64 that decodes to exactly 32 bytes for provider credential encryption.
export APP_ELMO_ENCRYPTION_KEY="$(derive_entropy "ausilio-elmo-encryption-key" | openssl dgst -sha256 -binary | openssl base64 -A)"

# --- Public URL ---
ELMO_DEFAULT_APP_URL="http://localhost:8096"
ELMO_APP_PORT="8096"
_elmo_app_url="${APP_ELMO_APP_URL:-${APP_URL:-}}"
if [ -z "${_elmo_app_url}" ]; then
  _elmo_app_url="${ELMO_DEFAULT_APP_URL}"
else
  case "${_elmo_app_url}" in
    https://*) ;;
    http://localhost|http://localhost[:/]*|http://127.0.0.1|http://127.0.0.1[:/]*|http://\[::1\]|http://\[::1\][:/]*) ;;
    *)
      echo "[elmo] Ignoring APP_URL=${_elmo_app_url}: Elmo needs an HTTPS URL (or localhost) to serve MCP. Using ${ELMO_DEFAULT_APP_URL}." >&2
      _elmo_app_url="${ELMO_DEFAULT_APP_URL}"
      ;;
  esac
fi
export APP_ELMO_APP_URL="${_elmo_app_url%/}"

# --- Accepted browser origins ---
_elmo_origins=""
_elmo_add_origin() {
  [ -n "$1" ] || return 0
  case ",${_elmo_origins}," in
    *",$1,"*) return 0 ;;
  esac
  if [ -z "${_elmo_origins}" ]; then
    _elmo_origins="$1"
  else
    _elmo_origins="${_elmo_origins},$1"
  fi
}

case "${APP_ELMO_APP_URL}" in
  https://*)
    _elmo_add_origin "${APP_ELMO_APP_URL}"
    ;;
  *)
    _elmo_add_origin "http://localhost:${ELMO_APP_PORT}"
    _elmo_add_origin "http://127.0.0.1:${ELMO_APP_PORT}"
    for _elmo_host in "${DEVICE_HOSTNAME:-}" "${DEVICE_DOMAIN_NAME:-}" "${APP_DOMAIN:-}"; do
      if [ -n "${_elmo_host}" ]; then
        _elmo_add_origin "http://${_elmo_host}:${ELMO_APP_PORT}"
        _elmo_add_origin "https://${_elmo_host}"
      fi
    done
    _elmo_ips="$(hostname --all-ip-addresses 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    for _elmo_ip in ${_elmo_ips}; do
      _elmo_add_origin "http://${_elmo_ip}:${ELMO_APP_PORT}"
    done
    ;;
esac
export APP_ELMO_BETTER_AUTH_TRUSTED_ORIGINS="${_elmo_origins}"
unset _elmo_host _elmo_ips _elmo_ip 2>/dev/null || true

# --- SCRAPE_TARGETS ---
_elmo_targets="${APP_ELMO_SCRAPE_TARGETS:-${SCRAPE_TARGETS:-}}"
if [ -z "${_elmo_targets}" ]; then
  if [ -n "${APP_ELMO_BRIGHTDATA_API_TOKEN:-}" ]; then
    _elmo_targets="chatgpt:brightdata:online,google-ai-mode:brightdata:online,google-ai-overview:brightdata:online,gemini:brightdata:online,perplexity:brightdata:online,copilot:brightdata:online"
  elif [ -n "${APP_ELMO_CLORO_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:cloro:online,google-ai-mode:cloro:online,google-ai-overview:cloro:online,gemini:cloro:online,perplexity:cloro:online,copilot:cloro:online"
  elif [ -n "${APP_ELMO_SEARCHAPI_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:searchapi:online,google-ai-mode:searchapi:online,google-ai-overview:searchapi:online,gemini:searchapi:online,perplexity:searchapi:online,copilot:searchapi:online"
  elif [ -n "${APP_ELMO_OLOSTEP_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:olostep:online,google-ai-mode:olostep:online,google-ai-overview:olostep:online,gemini:olostep:online,perplexity:olostep:online,copilot:olostep:online"
  elif [ -n "${APP_ELMO_OXYLABS_USERNAME:-}" ] && [ -n "${APP_ELMO_OXYLABS_PASSWORD:-}" ]; then
    _elmo_targets="chatgpt:oxylabs:online,google-ai-mode:oxylabs:online,google-ai-overview:oxylabs:online,perplexity:oxylabs:online"
  elif [ -n "${APP_ELMO_DATAFORSEO_LOGIN:-}" ] && [ -n "${APP_ELMO_DATAFORSEO_PASSWORD:-}" ]; then
    _elmo_targets="chatgpt:dataforseo:online,google-ai-mode:dataforseo:online,google-ai-overview:dataforseo:online,gemini:dataforseo:online,perplexity:dataforseo:online"
  elif [ -n "${APP_ELMO_OPENROUTER_API_KEY:-}" ]; then
    _elmo_targets="claude:openrouter:anthropic/claude-haiku-5.5:online"
  elif [ -n "${APP_ELMO_ANTHROPIC_API_KEY:-}" ]; then
    _elmo_targets="claude:anthropic-api:claude-haiku-5-5:online"
  elif [ -n "${APP_ELMO_OPENAI_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:openai-api:gpt-6-luna:online"
  elif [ -n "${APP_ELMO_MISTRAL_API_KEY:-}" ]; then
    _elmo_targets="mistral:mistral-api:mistral-medium-latest:online"
  fi
fi
export APP_ELMO_SCRAPE_TARGETS="${_elmo_targets}"

# --- Data directories ---
mkdir -p "${ELMO_APP_DIR}/postgres_data" 2>/dev/null || true

# --- Persist the derived values for the operator ---
ELMO_EXPORTS_ENV="${ELMO_APP_DIR}/exports.env"
{
  printf 'APP_ELMO_DB_PASSWORD=%s\n' "${APP_ELMO_DB_PASSWORD}"
  printf 'APP_ELMO_BETTER_AUTH_SECRET=%s\n' "${APP_ELMO_BETTER_AUTH_SECRET}"
  printf 'APP_ELMO_ENCRYPTION_KEY=%s\n' "${APP_ELMO_ENCRYPTION_KEY}"
  printf 'APP_ELMO_APP_URL=%s\n' "${APP_ELMO_APP_URL}"
  printf 'APP_ELMO_BETTER_AUTH_TRUSTED_ORIGINS=%s\n' "${APP_ELMO_BETTER_AUTH_TRUSTED_ORIGINS}"
  printf 'APP_ELMO_SCRAPE_TARGETS=%s\n' "${APP_ELMO_SCRAPE_TARGETS}"
} > "${ELMO_EXPORTS_ENV}" 2>/dev/null || true
chmod 600 "${ELMO_EXPORTS_ENV}" 2>/dev/null || true

unset ELMO_CONFIG_ENV ELMO_DEFAULT_APP_URL ELMO_APP_PORT _elmo_app_url _elmo_origins _elmo_targets
unset ELMO_EXPORTS_ENV _elmo_ips _elmo_ip 2>/dev/null || true
unset -f _elmo_add_origin 2>/dev/null || true
