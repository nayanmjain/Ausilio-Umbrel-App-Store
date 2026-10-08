# Baserow for Umbrel: accept the app on every local address.
# Baserow renders a "Site not found" page when the browser URL's host does not
# match BASEROW_PUBLIC_URL, so register the device hostname, app domain, and
# LAN IPs as extra public URLs (and Django allowed hosts).
# Sourced by Umbrel on install/start. Must stay idempotent and fast.
_baserow_urls="http://${DEVICE_HOSTNAME}:8092"
_baserow_hosts="${DEVICE_HOSTNAME}"
if [ -n "${APP_DOMAIN:-}" ]; then
  _baserow_urls="${_baserow_urls},http://${APP_DOMAIN}:8092"
  _baserow_hosts="${_baserow_hosts},${APP_DOMAIN}"
fi
_baserow_ips=$(hostname --all-ip-addresses 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
for _ip in ${_baserow_ips}; do
  _baserow_urls="${_baserow_urls},http://${_ip}:8092"
  _baserow_hosts="${_baserow_hosts},${_ip}"
done
export APP_BASEROW_EXTRA_PUBLIC_URLS="${_baserow_urls}"
export APP_BASEROW_EXTRA_HOSTS="${_baserow_hosts}"
unset _baserow_urls _baserow_hosts _baserow_ips _ip 2>/dev/null || true
