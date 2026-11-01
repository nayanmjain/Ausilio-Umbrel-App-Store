# Elmo for Umbrel: derive stable secrets, render the runtime env file, and
# create the Postgres data directory.
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

# Accept APP_ELMO_-prefixed spellings when the upstream name is unset, so both
# styles work in config.env without duplicating the list elsewhere.
for _elmo_name in \
  BRIGHTDATA_API_TOKEN CLORO_API_KEY SEARCHAPI_API_KEY OLOSTEP_API_KEY \
  OXYLABS_USERNAME OXYLABS_PASSWORD DATAFORSEO_LOGIN DATAFORSEO_PASSWORD \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY MISTRAL_API_KEY \
  TYPESAFE_API_KEY JINA_API_KEY REPROCESS_DAYS ONBOARDING_LLM_TARGET \
  RUNS_PER_PROMPT DEFAULT_DELAY_HOURS SCRAPE_TARGETS APP_URL DISABLE_TELEMETRY \
  ELMO_ENCRYPTION_KEY_OLD
do
  eval "_elmo_native=\"\${${_elmo_name}:-}\""
  if [ -z "${_elmo_native}" ]; then
    eval "_elmo_prefixed=\"\${APP_ELMO_${_elmo_name}:-}\""
    if [ -n "${_elmo_prefixed}" ]; then
      eval "export ${_elmo_name}=\"\${_elmo_prefixed}\""
    fi
  fi
done
unset _elmo_name _elmo_native _elmo_prefixed

# --- Secrets (deterministic per Umbrel seed, stable across restarts/upgrades) ---
# Hex keeps the database password safe inside DATABASE_URL.
export APP_ELMO_DB_PASSWORD="$(derive_entropy "ausilio-elmo-db-password" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-32)"
APP_ELMO_BETTER_AUTH_SECRET="$(derive_entropy "ausilio-elmo-better-auth-secret" | openssl dgst -sha256 -hex | awk '{print $2}' | cut -c1-64)"
# Elmo requires standard base64 that decodes to exactly 32 bytes for provider
# credential encryption.
ELMO_ENCRYPTION_KEY="$(derive_entropy "ausilio-elmo-encryption-key" | openssl dgst -sha256 -binary | openssl base64 -A)"
export APP_ELMO_BETTER_AUTH_SECRET ELMO_ENCRYPTION_KEY

# --- Public URL ---
# Elmo refuses to start when APP_URL is a plain-HTTP non-localhost origin: its
# MCP endpoint binds access tokens to the origin, and MCP clients reject
# anything that is not HTTPS. The Umbrel default therefore stays localhost
# while the app is reached over the LAN; browsers may use any trusted origin.
# Set APP_URL=https://... only when serving Elmo from a domain over HTTPS.
ELMO_DEFAULT_APP_URL="http://localhost:8096"
ELMO_APP_PORT="8096"
_elmo_app_url="${APP_URL:-}"
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
_elmo_app_url="${_elmo_app_url%/}"

# --- Accepted browser origins ---
# Better Auth checks the browser's Origin header against the base URL, so with
# APP_URL=localhost, sign-in from http://umbrel.local:8096 (or a LAN IP) only
# works when those origins are trusted explicitly. Umbrel exposes the app on
# the device hostname, the device domain, the app domain, and raw LAN IPs.
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

case "${_elmo_app_url}" in
  https://*)
    # Secure cookies: the browser must use this exact HTTPS origin.
    _elmo_add_origin "${_elmo_app_url}"
    ;;
  *)
    _elmo_add_origin "http://localhost:${ELMO_APP_PORT}"
    _elmo_add_origin "http://127.0.0.1:${ELMO_APP_PORT}"
    for _elmo_host in "${DEVICE_HOSTNAME:-}" "${DEVICE_DOMAIN_NAME:-}" "${APP_DOMAIN:-}"; do
      if [ -n "${_elmo_host}" ]; then
        _elmo_add_origin "http://${_elmo_host}:${ELMO_APP_PORT}"
        # Umbrel's own reverse proxy serves apps over HTTPS on 443, too.
        _elmo_add_origin "https://${_elmo_host}"
      fi
    done
    _elmo_ips="$(hostname --all-ip-addresses 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    for _elmo_ip in ${_elmo_ips}; do
      _elmo_add_origin "http://${_elmo_ip}:${ELMO_APP_PORT}"
    done
    ;;
esac
unset _elmo_host _elmo_ips _elmo_ip 2>/dev/null || true

# --- SCRAPE_TARGETS ---
# Elmo tracks models through a scraper (live ChatGPT / Google AI Mode /
# Perplexity / ...) or a direct model API. Derive a sensible default from the
# first configured provider unless the operator set SCRAPE_TARGETS explicitly.
# Order matches common self-host setups: a real scraper first, then the direct
# APIs (OpenRouter is also the cheapest way to run Jev).
_elmo_targets="${SCRAPE_TARGETS:-}"
if [ -z "${_elmo_targets}" ]; then
  if [ -n "${BRIGHTDATA_API_TOKEN:-}" ]; then
    _elmo_targets="chatgpt:brightdata:online,google-ai-mode:brightdata:online,google-ai-overview:brightdata:online,gemini:brightdata:online,perplexity:brightdata:online,copilot:brightdata:online"
  elif [ -n "${CLORO_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:cloro:online,google-ai-mode:cloro:online,google-ai-overview:cloro:online,gemini:cloro:online,perplexity:cloro:online,copilot:cloro:online"
  elif [ -n "${SEARCHAPI_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:searchapi:online,google-ai-mode:searchapi:online,google-ai-overview:searchapi:online,gemini:searchapi:online,perplexity:searchapi:online,copilot:searchapi:online"
  elif [ -n "${OLOSTEP_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:olostep:online,google-ai-mode:olostep:online,google-ai-overview:olostep:online,gemini:olostep:online,perplexity:olostep:online,copilot:olostep:online"
  elif [ -n "${OXYLABS_USERNAME:-}" ] && [ -n "${OXYLABS_PASSWORD:-}" ]; then
    _elmo_targets="chatgpt:oxylabs:online,google-ai-mode:oxylabs:online,google-ai-overview:oxylabs:online,perplexity:oxylabs:online"
  elif [ -n "${DATAFORSEO_LOGIN:-}" ] && [ -n "${DATAFORSEO_PASSWORD:-}" ]; then
    _elmo_targets="chatgpt:dataforseo:online,google-ai-mode:dataforseo:online,google-ai-overview:dataforseo:online,gemini:dataforseo:online,perplexity:dataforseo:online"
  elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
    _elmo_targets="claude:openrouter:anthropic/claude-haiku-5.5:online"
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    _elmo_targets="claude:anthropic-api:claude-haiku-5-5:online"
  elif [ -n "${OPENAI_API_KEY:-}" ]; then
    _elmo_targets="chatgpt:openai-api:gpt-6-luna:online"
  elif [ -n "${MISTRAL_API_KEY:-}" ]; then
    _elmo_targets="mistral:mistral-api:mistral-medium-latest:online"
  fi
fi

# --- Data directories ---
mkdir -p "${ELMO_APP_DIR}/postgres_data" 2>/dev/null || true

# --- Runtime configuration passed to web + worker via env_file ---
# Rewritten on every start, so the installed copy is never edited by hand.
ELMO_RUNTIME_ENV="${ELMO_APP_DIR}/elmo-runtime.env"
{
  printf 'DEPLOYMENT_MODE=local\n'
  printf 'APP_URL=%s\n' "${_elmo_app_url}"
  printf 'BETTER_AUTH_SECRET=%s\n' "${APP_ELMO_BETTER_AUTH_SECRET}"
  printf 'BETTER_AUTH_TRUSTED_ORIGINS=%s\n' "${_elmo_origins}"
  printf 'ELMO_ENCRYPTION_KEY=%s\n' "${ELMO_ENCRYPTION_KEY}"
  printf 'DATABASE_URL=postgres://postgres:%s@postgres:5432/elmo\n' "${APP_ELMO_DB_PASSWORD}"
  printf 'DISABLE_TELEMETRY=%s\n' "${DISABLE_TELEMETRY:-1}"
  printf 'DO_NOT_TRACK=1\n'
  if [ -n "${_elmo_targets}" ]; then
    printf 'SCRAPE_TARGETS=%s\n' "${_elmo_targets}"
  fi

  # Provider keys plus optional tuning. Only non-empty values are written so
  # unset options keep Elmo's own defaults.
  for _elmo_optional in \
    OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY MISTRAL_API_KEY \
    BRIGHTDATA_API_TOKEN CLORO_API_KEY SEARCHAPI_API_KEY OLOSTEP_API_KEY \
    OXYLABS_USERNAME OXYLABS_PASSWORD DATAFORSEO_LOGIN DATAFORSEO_PASSWORD \
    TYPESAFE_API_KEY JINA_API_KEY REPROCESS_DAYS ONBOARDING_LLM_TARGET \
    RUNS_PER_PROMPT DEFAULT_DELAY_HOURS ELMO_ENCRYPTION_KEY_OLD
  do
    eval "_elmo_value=\"\${${_elmo_optional}:-}\""
    if [ -n "${_elmo_value}" ]; then
      printf '%s=%s\n' "${_elmo_optional}" "${_elmo_value}"
    fi
  done
  unset _elmo_optional _elmo_value
} > "${ELMO_RUNTIME_ENV}"
chmod 600 "${ELMO_RUNTIME_ENV}" 2>/dev/null || true

# --- Persist the derived values for the operator ---
# The secrets are reproducible from this Umbrel's seed, but a database restored
# onto a different device gets a different key: keep a copy next to the data it
# decrypts so it can be carried across.
ELMO_EXPORTS_ENV="${ELMO_APP_DIR}/exports.env"
{
  printf 'APP_ELMO_DB_PASSWORD=%s\n' "${APP_ELMO_DB_PASSWORD}"
  printf 'APP_ELMO_BETTER_AUTH_SECRET=%s\n' "${APP_ELMO_BETTER_AUTH_SECRET}"
  printf 'ELMO_ENCRYPTION_KEY=%s\n' "${ELMO_ENCRYPTION_KEY}"
  printf 'APP_URL=%s\n' "${_elmo_app_url}"
  printf 'BETTER_AUTH_TRUSTED_ORIGINS=%s\n' "${_elmo_origins}"
  printf 'SCRAPE_TARGETS=%s\n' "${_elmo_targets}"
} > "${ELMO_EXPORTS_ENV}" 2>/dev/null || true
chmod 600 "${ELMO_EXPORTS_ENV}" 2>/dev/null || true

unset ELMO_CONFIG_ENV ELMO_DEFAULT_APP_URL ELMO_APP_PORT _elmo_app_url _elmo_origins _elmo_targets
unset ELMO_RUNTIME_ENV ELMO_EXPORTS_ENV _elmo_ips _elmo_ip 2>/dev/null || true
unset -f _elmo_add_origin 2>/dev/null || true
