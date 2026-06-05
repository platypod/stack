#!/bin/sh
# Configure dnsmasq so that *.DOMAIN resolves to the Traefik LoadBalancer IP.
# Reads DOMAIN from values/dev/values.yaml if not set in the environment.
# Auto-detects TRAEFIK_IP from kubectl; prompts as a fallback.
#
# Usage:
#   bin/setup-dev-dns.sh
#   DOMAIN=platypod.local TRAEFIK_IP=192.168.122.200 bin/setup-dev-dns.sh

set -e

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { printf '\033[1;33m[info]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m     %s\n' "$*"; }
die()  { printf '\033[0;31m[error]\033[0m  %s\n' "$*" >&2; exit 1; }

prompt() {
  local var="$1" label="$2" default="$3"
  if [ -n "$(eval echo \$$var)" ]; then
    return
  fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default"
  else
    printf '%s: ' "$label"
  fi
  read -r input
  eval "$var=\"${input:-$default}\""
}

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$DOMAIN" ] && command -v yq > /dev/null 2>&1; then
  DOMAIN="$(yq e '.traefik.domain' "$SCRIPT_DIR/values/dev/values.yaml" 2>/dev/null || true)"
fi
prompt DOMAIN "Domain" "platypod.local"
[ -n "$DOMAIN" ] || die "DOMAIN is required."

if [ -z "$NAMESPACE" ] && command -v yq > /dev/null 2>&1; then
  NAMESPACE="$(yq e '.k8s.namespace' "$SCRIPT_DIR/values/dev/values.yaml" 2>/dev/null || true)"
fi
NAMESPACE="${NAMESPACE:-dev-platypod}"

# Auto-detect the Traefik LoadBalancer IP from kubectl if KUBECONFIG is set
# and Traefik is already deployed. Falls back to interactive prompt.
if [ -z "$TRAEFIK_IP" ] && command -v kubectl > /dev/null 2>&1 && [ -n "$KUBECONFIG" ]; then
  info "Auto-detecting Traefik LoadBalancer IP from cluster..."
  TRAEFIK_IP="$(kubectl get svc traefik -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "$TRAEFIK_IP" ]; then
    info "Detected Traefik IP: ${TRAEFIK_IP}"
  else
    info "Traefik service not found or no IP yet — enter manually."
  fi
fi

prompt TRAEFIK_IP "Traefik LoadBalancer IP" ""
[ -n "$TRAEFIK_IP" ] || die "TRAEFIK_IP is required (deploy core first: make deploy-one MODULE=core)."

DNSMASQ_CONF="/opt/homebrew/etc/dnsmasq.conf"
ENTRY="address=/.${DOMAIN}/${TRAEFIK_IP}"

# ---------------------------------------------------------------------------
# Install dnsmasq
# ---------------------------------------------------------------------------

if ! command -v dnsmasq > /dev/null 2>&1; then
  info "Installing dnsmasq via brew..."
  brew install dnsmasq
fi

# ---------------------------------------------------------------------------
# Configure dnsmasq
# ---------------------------------------------------------------------------

if grep -q "address=/\.${DOMAIN}/" "$DNSMASQ_CONF" 2>/dev/null; then
  sed -i '' "s|address=/\.${DOMAIN}/.*|${ENTRY}|" "$DNSMASQ_CONF"
  ok "Updated dnsmasq entry: ${ENTRY}"
else
  echo "$ENTRY" >> "$DNSMASQ_CONF"
  ok "Added dnsmasq entry: ${ENTRY}"
fi

# ---------------------------------------------------------------------------
# Configure macOS resolver
# ---------------------------------------------------------------------------

sudo mkdir -p /etc/resolver
printf 'nameserver 127.0.0.1\n' | sudo tee "/etc/resolver/${DOMAIN}" > /dev/null
ok "Resolver created: /etc/resolver/${DOMAIN}"

# ---------------------------------------------------------------------------
# Restart dnsmasq
# ---------------------------------------------------------------------------

sudo brew services restart dnsmasq
ok "dnsmasq restarted"

echo ""
ok "All *.${DOMAIN} → ${TRAEFIK_IP}"
