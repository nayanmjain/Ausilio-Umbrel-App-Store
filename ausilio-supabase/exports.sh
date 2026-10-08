# Supabase for Umbrel: derive secrets and provision managed config files.
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
# Secrets are deterministic per Umbrel seed (derive_entropy), so restarts and
# upgrades keep the same JWT secret, API keys and encryption keys.

# --- Secrets (deterministic, stable across restarts) ---
export APP_SUPABASE_JWT_SECRET="$(derive_entropy "ausilio-supabase-jwt-secret" | cut -c1-64)"
export APP_SUPABASE_SECRET_KEY_BASE="$(derive_entropy "ausilio-supabase-secret-key-base" | cut -c1-64)"
export APP_SUPABASE_VAULT_ENC_KEY="$(derive_entropy "ausilio-supabase-vault-enc-key" | cut -c1-32)"
export APP_SUPABASE_PG_META_CRYPTO_KEY="$(derive_entropy "ausilio-supabase-pg-meta-crypto-key" | cut -c1-32)"
export APP_SUPABASE_REALTIME_ENC_KEY="$(derive_entropy "ausilio-supabase-realtime-enc-key" | cut -c1-16)"
export APP_SUPABASE_S3_KEY_ID="$(derive_entropy "ausilio-supabase-s3-key-id" | cut -c1-32)"
export APP_SUPABASE_S3_KEY_SECRET="$(derive_entropy "ausilio-supabase-s3-key-secret" | cut -c1-64)"

# --- HS256 API keys (valid JWTs signed with the JWT secret) ---
_supabase_b64url() {
  openssl base64 -A 2>/dev/null | tr '+/' '-_' | tr -d '='
}
_supabase_sign_key() {
  _role="$1"
  _payload_json="{\"role\":\"${_role}\",\"iss\":\"supabase-demo\",\"iat\":1767225600,\"exp\":4102444800}"
  _header_b64="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
  _payload_b64="$(printf '%s' "${_payload_json}" | _supabase_b64url)"
  _sig="$(printf '%s' "${_header_b64}.${_payload_b64}" | openssl dgst -sha256 -hmac "${APP_SUPABASE_JWT_SECRET}" -binary | _supabase_b64url)"
  printf '%s' "${_header_b64}.${_payload_b64}.${_sig}"
}
export APP_SUPABASE_ANON_KEY="$(_supabase_sign_key anon)"
export APP_SUPABASE_SERVICE_KEY="$(_supabase_sign_key service_role)"
unset -f _supabase_sign_key _supabase_b64url 2>/dev/null || true

# --- Data directories ---
mkdir -p "${APP_DATA_DIR}/envoy" "${APP_DATA_DIR}/db-init" "${APP_DATA_DIR}/functions/main" \
  "${APP_DATA_DIR}/functions/hello" "${APP_DATA_DIR}/storage" "${APP_DATA_DIR}/snippets" \
  "${APP_DATA_DIR}/db/data" "${APP_DATA_DIR}/db-config" "${APP_DATA_DIR}/deno-cache" 2>/dev/null || true

# --- Managed files (rewritten every start; do not edit, they track upstream) ---

cat > "${APP_DATA_DIR}/envoy/envoy.yaml" <<'SUPABASE_EOF_ENVOY_ENVOY_YAML'
dynamic_resources:
  cds_config:
    path_config_source:
      path: /etc/envoy/cds.yaml
    resource_api_version: V3
  lds_config:
    path_config_source:
      path: /etc/envoy/lds.yaml
    resource_api_version: V3

node:
  cluster: supabase_cluster
  id: supabase_node

overload_manager:
  resource_monitors:
    - name: envoy.resource_monitors.global_downstream_max_connections
      typed_config:
        '@type': >-
          type.googleapis.com/envoy.extensions.resource_monitors.downstream_connections.v3.DownstreamConnectionsConfig
        max_active_downstream_connections: 30000

admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
SUPABASE_EOF_ENVOY_ENVOY_YAML

cat > "${APP_DATA_DIR}/envoy/cds.yaml" <<'SUPABASE_EOF_ENVOY_CDS_YAML'
resources:
  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: auth
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: auth
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: auth
                    port_value: 9999
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /health
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: rest
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: rest
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: rest
                    port_value: 3000
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: realtime
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: realtime
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: realtime-dev.supabase-realtime
                    port_value: 4000
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: storage
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: storage
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: storage
                    port_value: 5000
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /status
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: functions
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: functions
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: functions
                    port_value: 9000
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        tcp_health_check: {}
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: meta
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: meta
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: meta
                    port_value: 8080
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /health
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000

  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: studio
    connect_timeout: 5s
    type: STRICT_DNS
    dns_refresh_rate: 5s
    dns_failure_refresh_rate:
      base_interval: 1s
      max_interval: 1s
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: studio
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: studio
                    port_value: 3000
    health_checks:
      - timeout: 2s
        interval: 5s
        unhealthy_threshold: 3
        healthy_threshold: 2
        http_health_check:
          path: /project/default
    circuit_breakers:
      thresholds:
        - priority: DEFAULT
          max_connections: 10000
          max_pending_requests: 10000
          max_requests: 10000
SUPABASE_EOF_ENVOY_CDS_YAML

cat > "${APP_DATA_DIR}/envoy/lds.template.yaml" <<'SUPABASE_EOF_ENVOY_LDS_TEMPLATE_YAML'
resources:
  - '@type': type.googleapis.com/envoy.config.listener.v3.Listener
    name: supabase
    per_connection_buffer_limit_bytes: 32768  # 32 KiB

    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8000

    filter_chains:
      - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              '@type': >-
                type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              normalize_path: true
              merge_slashes: true
              path_with_escaped_slashes_action: REJECT_REQUEST
              use_remote_address: true
              common_http_protocol_options:
                headers_with_underscores_action: REJECT_REQUEST
              upgrade_configs:
                - upgrade_type: websocket
              access_log:
                - name: envoy.access_loggers.stdout
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
                    log_format:
                      text_format_source:
                        inline_string: "%DOWNSTREAM_REMOTE_ADDRESS_WITHOUT_PORT% - - [%START_TIME(%d/%b/%Y:%H:%M:%S %z)%] \"%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%\" %RESPONSE_CODE% %BYTES_SENT% \"%REQ(REFERER)%\" \"%REQ(USER-AGENT)%\"\n"

              route_config:
                name: supabase_route
                virtual_hosts:
                  - name: supabase_host
                    domains:
                      - '*'
                    cors:
                      allow_origin_string_match:
                        - safe_regex:
                            regex: ".*"
                      allow_methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD,CONNECT,TRACE"
                      allow_headers: "*"
                      expose_headers: "*"
                      max_age: "3600"
                    request_headers_to_add:
                      - header:
                          key: X-Forwarded-Host
                          value: "%REQ(:AUTHORITY)%"
                        append_action: ADD_IF_ABSENT
                      - header:
                          key: X-Forwarded-Port
                          value: "%DOWNSTREAM_LOCAL_PORT%"
                        append_action: ADD_IF_ABSENT
                    routes:
                      - match:
                          prefix: /auth/v1/verify
                        route:
                          cluster: auth
                          prefix_rewrite: /verify
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/verify
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /auth/v1/callback
                        route:
                          cluster: auth
                          prefix_rewrite: /callback
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/callback
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /auth/v1/authorize
                        route:
                          cluster: auth
                          prefix_rewrite: /authorize
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/authorize
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /auth/v1/.well-known/jwks.json
                        route:
                          cluster: auth
                          prefix_rewrite: /.well-known/jwks.json
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/.well-known/jwks.json
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /.well-known/oauth-authorization-server
                        route:
                          cluster: auth
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /.well-known/oauth-authorization-server
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /auth/v1/sso/saml/acs
                        route:
                          cluster: auth
                          prefix_rewrite: /sso/saml/acs
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/sso/saml/acs
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /auth/v1/sso/saml/metadata
                        route:
                          cluster: auth
                          prefix_rewrite: /sso/saml/metadata
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/sso/saml/metadata
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - name: functions-v1-all
                        match:
                          prefix: /functions/v1/
                        route:
                          cluster: functions
                          prefix_rewrite: /
                          # Allow the runtime's 400s wall clock to expire first.
                          timeout: 410s
                          # Limit inactivity, matching Kong's read_timeout.
                          idle_timeout: 160s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /functions/v1/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /storage/v1/
                        route:
                          cluster: storage
                          prefix_rewrite: /
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /storage/v1
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - name: auth-v1-protected
                        match:
                          prefix: /auth/v1/
                        route:
                          cluster: auth
                          prefix_rewrite: /
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /auth/v1/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true

                      - name: rest-v1-openapi-protected
                        match:
                          path: /rest/v1/
                        route:
                          cluster: rest
                          prefix_rewrite: /
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /rest/v1/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  admin:
                                    permissions:
                                      - any: true
                                    principals:
                                      - header:
                                          name: apikey
                                          string_match:
                                            exact: '${SERVICE_ROLE_KEY}'
                                      - header:
                                          name: apikey
                                          string_match:
                                            exact: '${SERVICE_ROLE_KEY_ASYMMETRIC}'

                      - name: rest-v1-protected
                        match:
                          prefix: /rest/v1/
                        route:
                          cluster: rest
                          prefix_rewrite: /
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /rest/v1/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true

                      - name: graphql-v1-protected
                        match:
                          prefix: /graphql/v1
                        route:
                          cluster: rest
                          prefix_rewrite: /rpc/graphql
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /graphql/v1
                            append_action: ADD_IF_ABSENT
                          - header:
                              key: Content-Profile
                              value: graphql_public
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true

                      - name: realtime-v1-api-openapi-blocked
                        match:
                          prefix: /realtime/v1/api/openapi
                        route:
                          cluster: realtime
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /realtime/v1/api/openapi
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: DENY
                                policies:
                                  deny_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - name: realtime-v1-api-tenants-blocked
                        match:
                          prefix: /realtime/v1/api/tenants
                        route:
                          cluster: realtime
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /realtime/v1/api/tenants
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: DENY
                                policies:
                                  deny_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - name: realtime-v1-api-protected
                        match:
                          prefix: /realtime/v1/api
                        route:
                          cluster: realtime
                          prefix_rewrite: /api
                          timeout: 30s
                          host_rewrite_literal: realtime-dev.supabase-realtime
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /realtime/v1/api
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true

                      - name: realtime-v1-ws-protected
                        match:
                          prefix: /realtime/v1/
                        route:
                          cluster: realtime
                          prefix_rewrite: /socket/
                          timeout: 30s
                          host_rewrite_literal: realtime-dev.supabase-realtime
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /realtime/v1/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true

                      - name: pg-protected
                        match:
                          prefix: /pg/
                        route:
                          cluster: meta
                          prefix_rewrite: /
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /pg/
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.cors:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
                            allow_origin_string_match:
                              - exact: '${SUPABASE_PUBLIC_URL}'
                              - safe_regex:
                                  regex: 'https?://(localhost|127\.0\.0\.1)(:[0-9]+)?'
                            allow_methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD"
                            allow_headers: "*"
                            expose_headers: "*"
                            max_age: "3600"

                      - match:
                          prefix: /api/mcp
                        route:
                          cluster: studio
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /api/mcp
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: DENY
                                policies:
                                  deny_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

                      - match:
                          prefix: /mcp
                        route:
                          cluster: studio
                          prefix_rewrite: /api/mcp
                          timeout: 30s
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /mcp
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.basic_auth:
                            '@type': >-
                              type.googleapis.com/envoy.config.route.v3.FilterConfig
                            disabled: true
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            # Block access to /mcp by default
                            rbac:
                              rules:
                                action: DENY
                                policies:
                                  deny_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true
                            # Enable local access (danger zone!)
                            # 1. Comment out the 'rbac' block above.
                            # 2. Uncomment and adjust the 'rbac' block below.
                            # 3. Add or adjust your local IPs in 'principals'.
                            #rbac:
                            #  rules:
                            #    action: ALLOW
                            #    policies:
                            #      allow_local:
                            #        permissions:
                            #          - any: true
                            #        principals:
                            #          - direct_remote_ip:
                            #              address_prefix: 127.0.0.1
                            #              prefix_len: 32
                            #          - direct_remote_ip:
                            #              address_prefix: ::1
                            #              prefix_len: 128

                      - match:
                          prefix: /
                        route:
                          cluster: studio
                          timeout: 30s
                        request_headers_to_remove:
                          - authorization
                        request_headers_to_add:
                          - header:
                              key: X-Forwarded-Prefix
                              value: /
                            append_action: ADD_IF_ABSENT
                        typed_per_filter_config:
                          envoy.filters.http.rbac:
                            '@type': >-
                              type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute
                            rbac:
                              rules:
                                action: ALLOW
                                policies:
                                  allow_all:
                                    permissions:
                                      - any: true
                                    principals:
                                      - any: true

              http_filters:
                - name: envoy.filters.http.cors
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors

                - name: envoy.filters.http.basic_auth
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.basic_auth.v3.BasicAuth
                    users:
                      inline_string: '${DASHBOARD_BASIC_AUTH}'

                # Copies ?apikey=... from the URL into the apikey header when clients omit the header.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local FUNCTIONS_ROUTE = "functions-v1-all"
                      local FUNCTIONS_PREFIX = "/functions/v1/"

                      local function is_functions_request(request_handle, headers)
                        if request_handle:streamInfo():routeName() == FUNCTIONS_ROUTE then
                          return true
                        end

                        local path = headers:get(":path")
                        if path == nil then
                          return false
                        end

                        return string.sub(path, 1, string.len(FUNCTIONS_PREFIX)) == FUNCTIONS_PREFIX
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        if is_functions_request(request_handle, headers) then
                          return
                        end

                        if headers:get("apikey") ~= nil then
                          return
                        end

                        local path = headers:get(":path")
                        local query_start = string.find(path, "?", 1, true)
                        if query_start == nil then
                          return
                        end

                        local query = string.sub(path, query_start + 1)
                        for key, value in string.gmatch(query, "([^&]+)=([^&]*)") do
                          if key == "apikey" and value ~= "" then
                            headers:add("apikey", value)
                            return
                          end
                        end
                      end

                # Returns 401 for missing/invalid API keys on protected API routes.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local ANON_KEY = "${ANON_KEY}"
                      local SERVICE_ROLE_KEY = "${SERVICE_ROLE_KEY}"
                      local SUPABASE_PUBLISHABLE_KEY = "${SUPABASE_PUBLISHABLE_KEY}"
                      local SUPABASE_SECRET_KEY = "${SUPABASE_SECRET_KEY}"
                      local ANON_KEY_ASYMMETRIC = "${ANON_KEY_ASYMMETRIC}"
                      local SERVICE_ROLE_KEY_ASYMMETRIC = "${SERVICE_ROLE_KEY_ASYMMETRIC}"
                      local TRANSLATION_ENABLED = SUPABASE_SECRET_KEY ~= "" and SUPABASE_PUBLISHABLE_KEY ~= "" and SERVICE_ROLE_KEY_ASYMMETRIC ~= "" and ANON_KEY_ASYMMETRIC ~= ""

                      local PROTECTED_ROUTES = {
                        ["auth-v1-protected"] = true,
                        ["rest-v1-openapi-protected"] = true,
                        ["rest-v1-protected"] = true,
                        ["graphql-v1-protected"] = true,
                        ["realtime-v1-api-protected"] = true,
                        ["realtime-v1-ws-protected"] = true,
                        ["pg-protected"] = true,
                      }

                      local function is_protected_route(route_name)
                        if route_name == nil or route_name == "" then
                          return false
                        end

                        return PROTECTED_ROUTES[route_name] == true
                      end

                      local function is_valid_apikey(apikey)
                        if apikey == nil or apikey == "" then
                          return false
                        end

                        if SERVICE_ROLE_KEY ~= "" and apikey == SERVICE_ROLE_KEY then
                          return true
                        end

                        if ANON_KEY ~= "" and apikey == ANON_KEY then
                          return true
                        end

                        if TRANSLATION_ENABLED and apikey == SUPABASE_SECRET_KEY then
                          return true
                        end

                        if TRANSLATION_ENABLED and apikey == SUPABASE_PUBLISHABLE_KEY then
                          return true
                        end

                        return false
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        local route_name = request_handle:streamInfo():routeName()
                        if not is_protected_route(route_name) then
                          return
                        end

                        if is_valid_apikey(headers:get("apikey")) then
                          return
                        end

                        request_handle:respond({
                          [":status"] = "401",
                          ["content-type"] = "text/plain",
                        }, "Unauthorized")
                      end

                # Translates the query parameter apikey into the matching internal JWT and rewrites the URL so only JWTs propagate downstream.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local FUNCTIONS_ROUTE = "functions-v1-all"
                      local FUNCTIONS_PREFIX = "/functions/v1/"
                      local SECRET_KEY = "${SUPABASE_SECRET_KEY}"
                      local PUBLISHABLE_KEY = "${SUPABASE_PUBLISHABLE_KEY}"
                      local SERVICE_ROLE_JWT = "${SERVICE_ROLE_KEY_ASYMMETRIC}"
                      local ANON_JWT = "${ANON_KEY_ASYMMETRIC}"
                      local TRANSLATION_ENABLED = SECRET_KEY ~= "" and PUBLISHABLE_KEY ~= "" and SERVICE_ROLE_JWT ~= "" and ANON_JWT ~= ""

                      local function is_functions_request(request_handle, headers)
                        if request_handle:streamInfo():routeName() == FUNCTIONS_ROUTE then
                          return true
                        end

                        local path = headers:get(":path")
                        if path == nil then
                          return false
                        end

                        return string.sub(path, 1, string.len(FUNCTIONS_PREFIX)) == FUNCTIONS_PREFIX
                      end

                      local function translate_apikey(apikey)
                        if apikey == nil or apikey == "" then
                          return nil
                        end

                        if not TRANSLATION_ENABLED then
                          return nil
                        end

                        if apikey == SECRET_KEY then
                          return SERVICE_ROLE_JWT
                        end

                        if apikey == PUBLISHABLE_KEY then
                          return ANON_JWT
                        end

                        return nil
                      end

                      local function extract_query_apikey(path)
                        if path == nil or path == "" then
                          return nil
                        end

                        local query_start = string.find(path, "?", 1, true)
                        if query_start == nil then
                          return nil
                        end

                        local query = string.sub(path, query_start + 1)
                        for key, value in string.gmatch(query, "([^&]+)=([^&]*)") do
                          if key == "apikey" and value ~= "" then
                            return value
                          end
                        end

                        return nil
                      end

                      local function replace_query_apikey(path, new_value)
                        if path == nil or path == "" or new_value == nil or new_value == "" then
                          return nil
                        end

                        local query_start = string.find(path, "?", 1, true)
                        if query_start == nil then
                          return nil
                        end

                        local base = string.sub(path, 1, query_start)
                        local query = string.sub(path, query_start + 1)
                        local updated = {}
                        local replaced = false

                        for part in string.gmatch(query, "([^&]+)") do
                          local key, value = string.match(part, "([^=]+)=(.*)")
                          if key == "apikey" then
                            part = key .. "=" .. new_value
                            replaced = true
                          end
                          table.insert(updated, part)
                        end

                        if not replaced then
                          return nil
                        end

                        return base .. table.concat(updated, "&")
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        if is_functions_request(request_handle, headers) then
                          return
                        end

                        local path = headers:get(":path")
                        local apikey = extract_query_apikey(path)
                        local translated = translate_apikey(apikey)

                        if translated == nil then
                          return
                        end

                        headers:replace("apikey", translated)

                        local rewritten_path = replace_query_apikey(path, translated)
                        if rewritten_path ~= nil then
                          headers:replace(":path", rewritten_path)
                        end
                      end

                # Translates an apikey header into the appropriate internal JWT for downstream RBAC checks.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local FUNCTIONS_ROUTE = "functions-v1-all"
                      local FUNCTIONS_PREFIX = "/functions/v1/"
                      local SECRET_KEY = "${SUPABASE_SECRET_KEY}"
                      local PUBLISHABLE_KEY = "${SUPABASE_PUBLISHABLE_KEY}"
                      local SERVICE_ROLE_JWT = "${SERVICE_ROLE_KEY_ASYMMETRIC}"
                      local ANON_JWT = "${ANON_KEY_ASYMMETRIC}"
                      local TRANSLATION_ENABLED = SECRET_KEY ~= "" and PUBLISHABLE_KEY ~= "" and SERVICE_ROLE_JWT ~= "" and ANON_JWT ~= ""

                      local function is_functions_request(request_handle, headers)
                        if request_handle:streamInfo():routeName() == FUNCTIONS_ROUTE then
                          return true
                        end

                        local path = headers:get(":path")
                        if path == nil then
                          return false
                        end

                        return string.sub(path, 1, string.len(FUNCTIONS_PREFIX)) == FUNCTIONS_PREFIX
                      end

                      local function translate_apikey(apikey)
                        if apikey == nil or apikey == "" then
                          return nil
                        end

                        if not TRANSLATION_ENABLED then
                          return nil
                        end

                        if apikey == SECRET_KEY then
                          return SERVICE_ROLE_JWT
                        end

                        if apikey == PUBLISHABLE_KEY then
                          return ANON_JWT
                        end

                        return nil
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        if is_functions_request(request_handle, headers) then
                          return
                        end

                        local translated = translate_apikey(headers:get("apikey"))
                        if translated ~= nil and translated ~= "" then
                          headers:replace("apikey", translated)
                        end
                      end

                # Mirrors apikey into x-api-key for realtime WS compatibility.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local REALTIME_WS_ROUTE = "realtime-v1-ws-protected"

                      function envoy_on_request(request_handle)
                        local route_name = request_handle:streamInfo():routeName()
                        if route_name ~= REALTIME_WS_ROUTE then
                          return
                        end

                        local headers = request_handle:headers()
                        local apikey = headers:get("apikey")
                        if apikey == nil or apikey == "" then
                          return
                        end

                        headers:replace("x-api-key", apikey)
                      end

                # Synthesizes an Authorization header (Bearer …) from apikey when callers don’t provide a real JWT header.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local FUNCTIONS_ROUTE = "functions-v1-all"
                      local FUNCTIONS_PREFIX = "/functions/v1/"
                      local REALTIME_WS_ROUTE = "realtime-v1-ws-protected"

                      local function is_functions_request(request_handle, headers)
                        if request_handle:streamInfo():routeName() == FUNCTIONS_ROUTE then
                          return true
                        end

                        local path = headers:get(":path")
                        if path == nil then
                          return false
                        end

                        return string.sub(path, 1, string.len(FUNCTIONS_PREFIX)) == FUNCTIONS_PREFIX
                      end

                      local function has_real_jwt(auth_header)
                        if auth_header == nil or auth_header == "" then
                          return false
                        end

                        if string.sub(auth_header, 1, 7) ~= "Bearer " then
                          return false
                        end

                        return string.sub(auth_header, 1, 10) ~= "Bearer sb_"
                      end

                      local function format_authorization(value)
                        if value == nil or value == "" then
                          return nil
                        end

                        if string.sub(value, 1, 7) == "Bearer " then
                          return value
                        end

                        return "Bearer " .. value
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        if request_handle:streamInfo():routeName() == REALTIME_WS_ROUTE then
                          return
                        end

                        if is_functions_request(request_handle, headers) then
                          return
                        end

                        if has_real_jwt(headers:get("authorization")) then
                          return
                        end

                        local apikey = headers:get("apikey")
                        local authorization_value = format_authorization(apikey)
                        if authorization_value ~= nil then
                          headers:replace("authorization", authorization_value)
                        end
                      end

                # Functions: mirror the platform behavior. Translate opaque sb_
                # keys to the pre-signed internal asymmetric JWT and inject it as a
                # raw `sb-api-key` header (no Bearer prefix), leaving Authorization
                # untouched. The apikey is read from the header only (+ an
                # Authorization `Bearer sb_` fallback) - no query-string source.
                # Strips any client-supplied sb-api-key (anti-spoof). Returns 401 only
                # for an sb_-prefixed key that is invalid/unregistered, or an
                # apikey-vs-bearer sb_ conflict; any non-sb_ value (legacy/user/
                # third-party JWT, or anything else) passes through to the runtime.
                - name: envoy.filters.http.lua
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                    inline_code: |
                      local FUNCTIONS_ROUTE = "functions-v1-all"
                      local FUNCTIONS_PREFIX = "/functions/v1/"
                      local PUBLISHABLE_KEY = "${SUPABASE_PUBLISHABLE_KEY}"
                      local SECRET_KEY = "${SUPABASE_SECRET_KEY}"
                      local ANON_JWT = "${ANON_KEY_ASYMMETRIC}"
                      local SERVICE_ROLE_JWT = "${SERVICE_ROLE_KEY_ASYMMETRIC}"
                      local TRANSLATION_ENABLED = SECRET_KEY ~= "" and PUBLISHABLE_KEY ~= "" and SERVICE_ROLE_JWT ~= "" and ANON_JWT ~= ""

                      local function is_functions_request(request_handle, headers)
                        if request_handle:streamInfo():routeName() == FUNCTIONS_ROUTE then
                          return true
                        end

                        local path = headers:get(":path")
                        if path == nil then
                          return false
                        end

                        return string.sub(path, 1, string.len(FUNCTIONS_PREFIX)) == FUNCTIONS_PREFIX
                      end

                      local function bearer_token(auth)
                        if auth == nil then
                          return nil
                        end

                        return string.match(auth, "^[Bb]earer%s+(.+)$")
                      end

                      local function unauthorized(request_handle, message)
                        request_handle:respond(
                          { [":status"] = "401", ["content-type"] = "text/plain" },
                          message
                        )
                      end

                      function envoy_on_request(request_handle)
                        local headers = request_handle:headers()
                        if not is_functions_request(request_handle, headers) then
                          return
                        end

                        -- Strip any client-supplied sb-api-key (anti-spoof).
                        headers:remove("sb-api-key")

                        -- No opaque keys configured: nothing to translate, pass through.
                        if not TRANSLATION_ENABLED then
                          return
                        end

                        local apikey = headers:get("apikey")
                        local bearer = bearer_token(headers:get("authorization"))

                        -- No key at all: pass through (verify_jwt:false / unauthenticated).
                        if (apikey == nil or apikey == "") and (bearer == nil or bearer == "") then
                          return
                        end

                        -- Conflict: bearer carries an sb_ key that disagrees with apikey.
                        if bearer ~= nil and string.sub(bearer, 1, 3) == "sb_"
                           and apikey ~= nil and apikey ~= "" and apikey ~= bearer then
                          unauthorized(request_handle, "Conflicting API keys")
                          return
                        end

                        -- Resolve the key from apikey, else an Authorization `Bearer sb_` fallback.
                        local key = apikey
                        if (key == nil or key == "") and bearer ~= nil and string.sub(bearer, 1, 3) == "sb_" then
                          key = bearer
                        end

                        -- Non-sb_ value (legacy/user/third-party JWT, or anything else):
                        -- pass through; the runtime verifies it.
                        if key == nil or key == "" or string.sub(key, 1, 3) ~= "sb_" then
                          return
                        end

                        -- sb_ key: translate publishable/secret, otherwise reject.
                        if key == SECRET_KEY then
                          headers:replace("sb-api-key", SERVICE_ROLE_JWT)
                        elseif key == PUBLISHABLE_KEY then
                          headers:replace("sb-api-key", ANON_JWT)
                        else
                          unauthorized(request_handle, "Invalid API key")
                        end
                      end

                - name: envoy.filters.http.rbac
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC
                    rules:
                      action: ALLOW
                      policies:
                        admin:
                          permissions:
                            - url_path:
                                path:
                                  prefix: /pg/
                          principals:
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${SERVICE_ROLE_KEY}'
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${SERVICE_ROLE_KEY_ASYMMETRIC}'
                        apikey:
                          permissions:
                            - url_path:
                                path:
                                  prefix: /auth/v1/
                            - url_path:
                                path:
                                  prefix: /rest/v1/
                            - url_path:
                                path:
                                  prefix: /realtime/v1/api
                            - url_path:
                                path:
                                  prefix: /realtime/v1/
                            - url_path:
                                path:
                                  prefix: /graphql/v1
                          principals:
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${SERVICE_ROLE_KEY}'
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${ANON_KEY}'
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${SERVICE_ROLE_KEY_ASYMMETRIC}'
                            - header:
                                name: apikey
                                string_match:
                                  exact: '${ANON_KEY_ASYMMETRIC}'
                - name: envoy.filters.http.router
                  typed_config:
                    '@type': >-
                      type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
SUPABASE_EOF_ENVOY_LDS_TEMPLATE_YAML

cat > "${APP_DATA_DIR}/envoy/docker-entrypoint.sh" <<'SUPABASE_EOF_ENVOY_DOCKER_ENTRYPOINT_SH'
#!/bin/sh
set -e

# Generate SHA1 base64 hash for Envoy basic auth user list
PASSWORD_HASH=$(printf '%s' "${DASHBOARD_PASSWORD}" | openssl sha1 -binary | openssl base64)
DASHBOARD_BASIC_AUTH="${DASHBOARD_USERNAME}:{SHA}${PASSWORD_HASH}"

echo "Generating Envoy configuration..."

# Process the lds.yaml template with environment variables using sed
# Using | as delimiter since JWT tokens contain /
sed -e "s|\${ANON_KEY}|${ANON_KEY}|g" \
    -e "s|\${ANON_KEY_ASYMMETRIC}|${ANON_KEY_ASYMMETRIC}|g" \
    -e "s|\${SERVICE_ROLE_KEY}|${SERVICE_ROLE_KEY}|g" \
    -e "s|\${SERVICE_ROLE_KEY_ASYMMETRIC}|${SERVICE_ROLE_KEY_ASYMMETRIC}|g" \
    -e "s|\${SUPABASE_PUBLISHABLE_KEY}|${SUPABASE_PUBLISHABLE_KEY}|g" \
    -e "s|\${SUPABASE_SECRET_KEY}|${SUPABASE_SECRET_KEY}|g" \
    -e "s|\${SUPABASE_PUBLIC_URL}|${SUPABASE_PUBLIC_URL}|g" \
    -e "s|\${DASHBOARD_BASIC_AUTH}|${DASHBOARD_BASIC_AUTH}|g" \
    /etc/envoy/lds.template.yaml > /etc/envoy/lds.yaml

if [ -n "$SUPABASE_SECRET_KEY" ] && \
   [ -n "$SUPABASE_PUBLISHABLE_KEY" ] && \
   [ -n "$SERVICE_ROLE_KEY_ASYMMETRIC" ] && \
   [ -n "$ANON_KEY_ASYMMETRIC" ]; then
  echo "Envoy sb_ key translation enabled"
else
  echo "Envoy running in legacy API key mode (sb_ keys disabled)"
fi

echo "Envoy configuration generated successfully"
echo "Starting Envoy..."

# Start Envoy
exec envoy -c /etc/envoy/envoy.yaml "$@"
SUPABASE_EOF_ENVOY_DOCKER_ENTRYPOINT_SH

cat > "${APP_DATA_DIR}/db-init/97-_supabase.sql" <<'SUPABASE_EOF_DB_INIT_97__SUPABASE_SQL'
\set pguser `echo "$POSTGRES_USER"`

CREATE DATABASE _supabase WITH OWNER :pguser;
SUPABASE_EOF_DB_INIT_97__SUPABASE_SQL

cat > "${APP_DATA_DIR}/db-init/99-realtime.sql" <<'SUPABASE_EOF_DB_INIT_99_REALTIME_SQL'
\set pguser `echo "$POSTGRES_USER"`

create schema if not exists _realtime;
alter schema _realtime owner to :pguser;
SUPABASE_EOF_DB_INIT_99_REALTIME_SQL

cat > "${APP_DATA_DIR}/db-init/98-webhooks.sql" <<'SUPABASE_EOF_DB_INIT_98_WEBHOOKS_SQL'
BEGIN;
  -- Create pg_net extension
  CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;
  -- Create supabase_functions schema
  CREATE SCHEMA supabase_functions AUTHORIZATION supabase_admin;
  GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
  ALTER DEFAULT PRIVILEGES IN SCHEMA supabase_functions GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
  ALTER DEFAULT PRIVILEGES IN SCHEMA supabase_functions GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
  ALTER DEFAULT PRIVILEGES IN SCHEMA supabase_functions GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
  -- supabase_functions.migrations definition
  CREATE TABLE supabase_functions.migrations (
    version text PRIMARY KEY,
    inserted_at timestamptz NOT NULL DEFAULT NOW()
  );
  -- Initial supabase_functions migration
  INSERT INTO supabase_functions.migrations (version) VALUES ('initial');
  -- supabase_functions.hooks definition
  CREATE TABLE supabase_functions.hooks (
    id bigserial PRIMARY KEY,
    hook_table_id integer NOT NULL,
    hook_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    request_id bigint
  );
  CREATE INDEX supabase_functions_hooks_request_id_idx ON supabase_functions.hooks USING btree (request_id);
  CREATE INDEX supabase_functions_hooks_h_table_id_h_name_idx ON supabase_functions.hooks USING btree (hook_table_id, hook_name);
  COMMENT ON TABLE supabase_functions.hooks IS 'Supabase Functions Hooks: Audit trail for triggered hooks.';
  CREATE FUNCTION supabase_functions.http_request()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    DECLARE
      request_id bigint;
      payload jsonb;
      url text := TG_ARGV[0]::text;
      method text := TG_ARGV[1]::text;
      headers jsonb DEFAULT '{}'::jsonb;
      params jsonb DEFAULT '{}'::jsonb;
      timeout_ms integer DEFAULT 1000;
    BEGIN
      IF url IS NULL OR url = 'null' THEN
        RAISE EXCEPTION 'url argument is missing';
      END IF;

      IF method IS NULL OR method = 'null' THEN
        RAISE EXCEPTION 'method argument is missing';
      END IF;

      IF TG_ARGV[2] IS NULL OR TG_ARGV[2] = 'null' THEN
        headers = '{"Content-Type": "application/json"}'::jsonb;
      ELSE
        headers = TG_ARGV[2]::jsonb;
      END IF;

      IF TG_ARGV[3] IS NULL OR TG_ARGV[3] = 'null' THEN
        params = '{}'::jsonb;
      ELSE
        params = TG_ARGV[3]::jsonb;
      END IF;

      IF TG_ARGV[4] IS NULL OR TG_ARGV[4] = 'null' THEN
        timeout_ms = 1000;
      ELSE
        timeout_ms = TG_ARGV[4]::integer;
      END IF;

      CASE
        WHEN method = 'GET' THEN
          SELECT http_get INTO request_id FROM net.http_get(
            url,
            params,
            headers,
            timeout_ms
          );
        WHEN method = 'POST' THEN
          payload = jsonb_build_object(
            'old_record', OLD,
            'record', NEW,
            'type', TG_OP,
            'table', TG_TABLE_NAME,
            'schema', TG_TABLE_SCHEMA
          );

          SELECT http_post INTO request_id FROM net.http_post(
            url,
            payload,
            params,
            headers,
            timeout_ms
          );
        ELSE
          RAISE EXCEPTION 'method argument % is invalid', method;
      END CASE;

      INSERT INTO supabase_functions.hooks
        (hook_table_id, hook_name, request_id)
      VALUES
        (TG_RELID, TG_NAME, request_id);

      RETURN NEW;
    END
  $function$;
  -- Supabase super admin
  DO
  $$
  BEGIN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;
  END
  $$;
  GRANT ALL PRIVILEGES ON SCHEMA supabase_functions TO supabase_functions_admin;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA supabase_functions TO supabase_functions_admin;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA supabase_functions TO supabase_functions_admin;
  ALTER USER supabase_functions_admin SET search_path = "supabase_functions";
  ALTER table "supabase_functions".migrations OWNER TO supabase_functions_admin;
  ALTER table "supabase_functions".hooks OWNER TO supabase_functions_admin;
  ALTER function "supabase_functions".http_request() OWNER TO supabase_functions_admin;
  GRANT supabase_functions_admin TO postgres;
  -- http_request() is SECURITY DEFINER and runs as supabase_functions_admin. Serializing
  -- NEW/OLD can touch objects in the extensions schema (PostGIS geometry reads
  -- extensions.spatial_ref_sys), so the role needs USAGE on it.
  GRANT USAGE ON SCHEMA extensions TO supabase_functions_admin;
  -- Remove unused supabase_pg_net_admin role
  DO
  $$
  BEGIN
    IF EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_pg_net_admin'
    )
    THEN
      REASSIGN OWNED BY supabase_pg_net_admin TO supabase_admin;
      DROP OWNED BY supabase_pg_net_admin;
      DROP ROLE supabase_pg_net_admin;
    END IF;
  END
  $$;
  -- pg_net grants when extension is already enabled
  DO
  $$
  BEGIN
    IF EXISTS (
      SELECT 1
      FROM pg_extension
      WHERE extname = 'pg_net'
    )
    THEN
      GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END
  $$;
  -- Event trigger for pg_net
  CREATE OR REPLACE FUNCTION extensions.grant_pg_net_access()
  RETURNS event_trigger
  LANGUAGE plpgsql
  AS $$
  BEGIN
    IF EXISTS (
      SELECT 1
      FROM pg_event_trigger_ddl_commands() AS ev
      JOIN pg_extension AS ext
      ON ev.objid = ext.oid
      WHERE ext.extname = 'pg_net'
    )
    THEN
      GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END;
  $$;
  COMMENT ON FUNCTION extensions.grant_pg_net_access IS 'Grants access to pg_net';
  DO
  $$
  BEGIN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_event_trigger
      WHERE evtname = 'issue_pg_net_access'
    ) THEN
      CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end WHEN TAG IN ('CREATE EXTENSION')
      EXECUTE PROCEDURE extensions.grant_pg_net_access();
    END IF;
  END
  $$;
  INSERT INTO supabase_functions.migrations (version) VALUES ('20210809183423_update_grants');
  ALTER function supabase_functions.http_request() SECURITY DEFINER;
  ALTER function supabase_functions.http_request() SET search_path = supabase_functions;
  REVOKE ALL ON FUNCTION supabase_functions.http_request() FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION supabase_functions.http_request() TO postgres, anon, authenticated, service_role;
COMMIT;
SUPABASE_EOF_DB_INIT_98_WEBHOOKS_SQL

cat > "${APP_DATA_DIR}/db-init/99-roles.sql" <<'SUPABASE_EOF_DB_INIT_99_ROLES_SQL'
-- NOTE: change to your own passwords for production environments
\set pgpass `echo "$POSTGRES_PASSWORD"`

ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
SUPABASE_EOF_DB_INIT_99_ROLES_SQL

cat > "${APP_DATA_DIR}/db-init/99-jwt.sql" <<'SUPABASE_EOF_DB_INIT_99_JWT_SQL'
\set jwt_exp `echo "$JWT_EXP"`

ALTER DATABASE postgres SET "app.settings.jwt_exp" TO :'jwt_exp';
SUPABASE_EOF_DB_INIT_99_JWT_SQL

cat > "${APP_DATA_DIR}/db-init/99-logs.sql" <<'SUPABASE_EOF_DB_INIT_99_LOGS_SQL'
\set pguser `echo "$POSTGRES_USER"`

\c _supabase
create schema if not exists _analytics;
alter schema _analytics owner to :pguser;
\c postgres
SUPABASE_EOF_DB_INIT_99_LOGS_SQL

cat > "${APP_DATA_DIR}/db-init/99-pooler.sql" <<'SUPABASE_EOF_DB_INIT_99_POOLER_SQL'
\set pguser `echo "$POSTGRES_USER"`

\c _supabase
create schema if not exists _supavisor;
alter schema _supavisor owner to :pguser;
\c postgres
SUPABASE_EOF_DB_INIT_99_POOLER_SQL

# --- Default edge functions (only installed when missing) ---

if [ ! -f "${APP_DATA_DIR}/functions/deno.jsonc" ]; then
cat > "${APP_DATA_DIR}/functions/deno.jsonc" <<'SUPABASE_EOF_FUNCTIONS_DENO_JSONC'
{
  "imports": {
    "@supabase/functions-js": "jsr:@supabase/functions-js@^2",
    "@supabase/server": "npm:@supabase/server@^1"
  }
}
SUPABASE_EOF_FUNCTIONS_DENO_JSONC
fi

if [ ! -f "${APP_DATA_DIR}/functions/main/index.ts" ]; then
cat > "${APP_DATA_DIR}/functions/main/index.ts" <<'SUPABASE_EOF_FUNCTIONS_MAIN_INDEX_TS'
import * as jose from 'jsr:@panva/jose@6'

console.log('main function started')

const MAX_WORKER_RETRIES = 3

const JWT_SECRET = Deno.env.get('JWT_SECRET')
const SUPABASE_JWKS = parseJwks(Deno.env.get('SUPABASE_JWKS'))
const LOCAL_JWKS = SUPABASE_JWKS ? jose.createLocalJWKSet(SUPABASE_JWKS) : null
const VERIFY_JWT = Deno.env.get('VERIFY_JWT') === 'true'

type AuthFailure = {
  code: RequestErrors
  message?: string
}

type FunctionFailure = {
  code: RequestErrors
  message: string
  status: number
}

export enum RequestErrors {
  InvalidLegacyJWT = 'UNAUTHORIZED_LEGACY_JWT',
  InvalidAsymmetricJWT = 'UNAUTHORIZED_ASYMMETRIC_JWT',
  InvalidTokenFormat = 'UNAUTHORIZED_INVALID_JWT_FORMAT',
  UnsupportedTokenAlgorithm = 'UNAUTHORIZED_UNSUPPORTED_TOKEN_ALGORITHM',
  MissingAuthHeader = 'UNAUTHORIZED_NO_AUTH_HEADER',
  NotFound = 'NOT_FOUND',
  BootError = 'BOOT_ERROR',
  EdgeFunctionError = 'EDGE_FUNCTION_ERROR',
  IdleTimeout = 'IDLE_TIMEOUT',
  WorkerResourceLimit = 'WORKER_RESOURCE_LIMIT',
  WorkerError = 'WORKER_ERROR',
  InvalidResponseStatusCode = 'INVALID_RESPONSE_STATUS_CODE',
}

function getFunctionErrorResponse({ code, message, status }: FunctionFailure): Response {
  return Response.json(
    { code, message },
    {
      status,
      headers: {
        'sb-error-code': code,
        'Access-Control-Expose-Headers': 'sb-error-code',
      },
    }
  )
}

function handleWorkerResponse(response: Response): Response {
  if (response.status < 500) return response

  const headers = new Headers(response.headers)
  headers.set('sb-error-code', RequestErrors.EdgeFunctionError)

  const exposedHeaders = (headers.get('Access-Control-Expose-Headers') ?? '')
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean)
  if (!exposedHeaders.some((name) => name.toLowerCase() === 'sb-error-code')) {
    exposedHeaders.push('sb-error-code')
  }
  headers.set('Access-Control-Expose-Headers', exposedHeaders.join(', '))

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  })
}

function resolveRuntimeError(e: unknown): FunctionFailure {
  // These error classes are supplied by Edge Runtime, rather than stock Deno.
  if (e instanceof Deno.errors.InvalidWorkerCreation) {
    return {
      code: RequestErrors.BootError,
      message: 'Function failed to start (please check logs)',
      status: 503,
    }
  }
  if (e instanceof Deno.errors.WorkerRequestCancelled) {
    return {
      code: RequestErrors.WorkerResourceLimit,
      message: 'Function failed due to not having enough compute resources (please check logs)',
      status: 546,
    }
  }
  if (e instanceof Deno.errors.WorkerRequestIdleTimeout) {
    return {
      code: RequestErrors.IdleTimeout,
      message: 'Request idle timeout limit (150s) reached',
      status: 504,
    }
  }
  // No dedicated runtime error class exists for invalid response statuses.
  // The Response constructor throws directly here or inside the user worker.
  if (
    (e instanceof RangeError || e instanceof Deno.errors.InvalidWorkerResponse) &&
    e.message.includes('is not equal to 101 and outside the range [200, 599]')
  ) {
    return {
      code: RequestErrors.InvalidResponseStatusCode,
      message: 'Function returned an invalid HTTP status code (please check logs)',
      status: 500,
    }
  }
  if (
    e instanceof Deno.errors.WorkerAlreadyRetired ||
    e instanceof Deno.errors.InvalidWorkerResponse
  ) {
    return {
      code: RequestErrors.WorkerError,
      message: 'Function exited due to an error (please check logs)',
      status: 500,
    }
  }
  return { code: RequestErrors.EdgeFunctionError, message: 'Internal Server Error', status: 500 }
}

// NOTE:(kallebysantos) We don't check for valid keys but just the bare array parsing,
// let this for 'jose' lib verification
export function parseJwks(raw: string | undefined): jose.JSONWebKeySet | null {
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw)
    if (parsed?.keys && Array.isArray(parsed.keys)) {
      return parsed as jose.JSONWebKeySet
    }
    return null
  } catch {
    return null
  }
}

/**
 * Extract JWT token from 'Authorization' header or fallback to 'sb-api-key' compatibility
 *
 * Parses the Authorization header to extract the Bearer token.
 * Expects format: "Bearer <token>"
 *
 * @param req - The HTTP request object
 * @returns The JWT token string or an authentication failure
 */
function extractBearerToken(authHeader: string | null): string | null {
  const tokenParts = (authHeader ?? '').trim().split(/\s+/)
  const [bearer, token] = tokenParts
  if (bearer.toLowerCase() !== 'bearer' || tokenParts.length !== 2 || !token) {
    return null
  }
  return token
}

function getAuthToken(req: Request): string | AuthFailure {
  const authHeader = req.headers.get('authorization')
  const sbApiKeyCompatibilityToken = req.headers.get('sb-api-key')

  if (!authHeader && !sbApiKeyCompatibilityToken) {
    return {
      code: RequestErrors.MissingAuthHeader,
      message: 'Missing authorization header',
    }
  }

  // NOTE:(kallebysantos) Compatibility mode is triggered when all conditions match:
  // - API proxy mints a temp token
  // - Original bearer is not present or is ApiKey
  const bearerToken = extractBearerToken(authHeader)
  const token = !bearerToken || bearerToken.startsWith('sb_')
    ? sbApiKeyCompatibilityToken
    : bearerToken

  if (!token) {
    return {
      code: RequestErrors.InvalidTokenFormat,
      message: 'Invalid JWT format',
    }
  }

  return token
}

function getAuthErrorResponse({ code, message = 'Invalid JWT' }: AuthFailure) {
  return Response.json(
    {
      code,
      message,
      // DEPRECATED: Retained for backward compatibility.
      msg: message,
    },
    {
      status: 401,
      headers: {
        'sb-error-code': code,
        'Access-Control-Expose-Headers': 'sb-error-code',
      },
    }
  )
}

async function isValidLegacyJWT(jwt: string): Promise<AuthFailure | null> {
  if (!JWT_SECRET) {
    console.error('JWT_SECRET not available for HS256 token verification')
    return { code: RequestErrors.InvalidLegacyJWT }
  }

  const encoder = new TextEncoder();
  const secretKey = encoder.encode(JWT_SECRET);

  try {
    await jose.jwtVerify(jwt, secretKey);
  } catch (e) {
    console.error('Symmetric Legacy JWT verification error', e);
    return { code: RequestErrors.InvalidLegacyJWT }
  }
  return null
}

async function isValidJWT(jwt: string): Promise<AuthFailure | null> {
  if (!LOCAL_JWKS) {
    console.error('JWKS not available for ES256/RS256 token verification')
    return { code: RequestErrors.InvalidAsymmetricJWT }
  }

  try {
    await jose.jwtVerify(jwt, LOCAL_JWKS);
  } catch (e) {
    console.error('Asymmetric JWT verification error', e);
    return { code: RequestErrors.InvalidAsymmetricJWT }
  }

  return null
}

/**
 * Verify JWT token, handling both legacy (HS256) and newer (ES256/RS256) algorithms
 * 
 * This function automatically detects the algorithm used in the token and applies
 * the appropriate verification method:
 * - HS256: Uses JWT_SECRET (symmetric key)
 * - ES256/RS256: Uses JWKS endpoint (asymmetric public keys)
 * 
 * This fix ensures compatibility with both legacy tokens and newer asymmetric tokens,
 * resolving the "Key for the ES256 algorithm must be of type CryptoKey" error.
 * 
 * @param jwt - The JWT token string to verify
 * @returns Authentication failure details, or null when verification succeeds
 */
async function isValidHybridJWT(jwt: string): Promise<AuthFailure | null> {
  let jwtAlgorithm: string | undefined
  try {
    jwtAlgorithm = jose.decodeProtectedHeader(jwt).alg
  } catch (e) {
    console.error('JWT format error', e)
    return {
      code: RequestErrors.InvalidTokenFormat,
      message: 'Invalid JWT format',
    }
  }

  if (!jwtAlgorithm) {
    return {
      code: RequestErrors.InvalidTokenFormat,
      message: 'Invalid JWT format',
    }
  }

  if (jwtAlgorithm === 'HS256') {
    console.log(`Legacy token type detected, attempting ${jwtAlgorithm} verification.`)

    return await isValidLegacyJWT(jwt)
  }

  if (jwtAlgorithm === 'ES256' || jwtAlgorithm === 'RS256') {
    return await isValidJWT(jwt)
  }

  return {
    code: RequestErrors.UnsupportedTokenAlgorithm,
    message: `Unsupported JWT algorithm ${jwtAlgorithm}`,
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'OPTIONS' && VERIFY_JWT) {
    try {
      const token = getAuthToken(req)
      if (typeof token !== 'string') {
        return getAuthErrorResponse(token)
      }
      const authFailure = await isValidHybridJWT(token)
      if (authFailure) {
        return getAuthErrorResponse(authFailure)
      }
    } catch (e) {
      console.error(e)
      return getAuthErrorResponse({
        code: RequestErrors.InvalidTokenFormat,
        message: 'Invalid JWT format',
      })
    }
  }

  const url = new URL(req.url)
  const { pathname } = url
  const path_parts = pathname.split('/')
  const service_name = path_parts[1]

  if (!service_name || service_name === '') {
    return getFunctionErrorResponse({
      code: RequestErrors.NotFound,
      message: 'Requested function was not found',
      status: 404,
    })
  }

  const servicePath = `/home/deno/functions/${service_name}`
  console.error(`serving the request with ${servicePath}`)

  try {
    const serviceInfo = await Deno.stat(servicePath)
    if (!serviceInfo.isDirectory) {
      return getFunctionErrorResponse({
        code: RequestErrors.NotFound,
        message: 'Requested function was not found',
        status: 404,
      })
    }
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) {
      return getFunctionErrorResponse({
        code: RequestErrors.NotFound,
        message: 'Requested function was not found',
        status: 404,
      })
    }
    console.error(e)
    return getFunctionErrorResponse({
      code: RequestErrors.BootError,
      message: 'Function failed to start (please check logs)',
      status: 503,
    })
  }

  const memoryLimitMb = 150
  // Keep the wall clock above the 150s request idle timeout configured in Compose.
  const workerTimeoutMs = 400_000
  const requestAbsentTimeoutMs = 60_000
  const noModuleCache = false
  // Using a common Import Map for all functions 
  // to use a scope 'deno.json' it must be dinamically resolved base on the 'service_name'
  const importMapPath = `/home/deno/functions/deno.jsonc`
  // SUPABASE_FUNCTION_SLUG is listed after the container env snapshot so
  // nothing in it can shadow the value, and it is per-request because only this
  // worker knows which function the request resolved to.
  const envVarsObj = { ...Deno.env.toObject(), SUPABASE_FUNCTION_SLUG: service_name }
  const envVars = Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]])

  const callWorker = async (req: Request, retriesLeft = MAX_WORKER_RETRIES): Promise<Response> => {
    // Preserve the body before fetch() can consume it, even on a failed attempt.
    // Must run before `new Request(req)` below, which takes over the body.
    // The unread retry branch can buffer the entire body in main-worker memory,
    // even when the first attempt succeeds.
    const retryReq = retriesLeft > 0 ? req.clone() : null

    try {
      const worker = await EdgeRuntime.userWorkers.create({
        servicePath,
        memoryLimitMb,
        workerTimeoutMs,
        context: { supervisor: { requestAbsentTimeoutMs } },
        noModuleCache,
        importMapPath,
        envVars,
      })
      // Gateway-minted internal JWT is for this router only; never expose it to user functions.
      const userReq = new Request(req)
      userReq.headers.delete('sb-api-key')
      EdgeRuntime.applySupabaseTag(req, userReq)
      return handleWorkerResponse(await worker.fetch(userReq))
    } catch (e) {
      // Retirement rejects before dispatch, so user code has not run yet.
      if (e instanceof Deno.errors.WorkerAlreadyRetired && retryReq) {
        console.warn(`${service_name}: worker retired before dispatch; retrying (${retriesLeft} left)`)
        // Request.clone() does not copy the tag that connects streaming to the client.
        EdgeRuntime.applySupabaseTag(req, retryReq)
        return await callWorker(retryReq, retriesLeft - 1)
      }

      console.error(e)
      return getFunctionErrorResponse(resolveRuntimeError(e))
    }
  }

  return await callWorker(req)
})
SUPABASE_EOF_FUNCTIONS_MAIN_INDEX_TS
fi

if [ ! -f "${APP_DATA_DIR}/functions/hello/index.ts" ]; then
cat > "${APP_DATA_DIR}/functions/hello/index.ts" <<'SUPABASE_EOF_FUNCTIONS_HELLO_INDEX_TS'
// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts"
import { withSupabase } from "@supabase/server"

// Logs are visible from 'functions' container inspector
console.log("Hello from Functions!");

// This endpoint uses 'publishable' | 'secret' access, apiKey is required.
// Use publishable for Client-facing, key-validated endpoints
// Use secret for Server-to-server, internal calls
export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    // Called by another service with a secret key
    // ctx.supabaseAdmin bypasses RLS — use for privileged operations
    /*
    if (ctx.authMode === "secret") {
      const { user_id } = await req.json();
      const { data } = await ctx.supabaseAdmin.auth.admin.getUserById(user_id);

      return Response.json({
        email: data?.user?.email,
      });
    }
    */

    return Response.json({ message: "Hello from Edge Functions!" });
  }),
};

// To invoke:
// curl 'http://localhost:<API_GW_HTTP_PORT>/functions/v1/hello' \
//   --header 'apiKey: <sb_publishable/sb_secret key>'

SUPABASE_EOF_FUNCTIONS_HELLO_INDEX_TS
fi

