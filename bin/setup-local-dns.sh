#!/bin/sh
# Configure macOS to use Adguard as its system DNS server with 1.1.1.1 as
# fallback. Adguard handles the *.DOMAIN → Traefik rewrite internally, and (in
# prod) the k8s.platypod.lan → control-plane rewrite (adguard.rewrites in
# clusters/prd/secrets.enc.yaml in platypod-sops) — see ../infra/docs/decisions.md.
#
# When the cluster is suspended, Adguard doesn't respond; macOS falls through
# to 1.1.1.1 for internet DNS. *.DOMAIN (and, in prod, k8s.platypod.lan)
# simply won't resolve — that's expected when the cluster is down. For prod
# specifically, that means losing kubectl DNS exactly when you'd want it to
# fix the cluster: Terraform's extraHostEntries (api_host_entries in
# cluster-core/locals.tf) covers the Talos NODES, not your laptop. Keep a
# manual /etc/hosts line for k8s.platypod.lan on any machine you'll run
# kubectl from as a break-glass fallback — see ../infra/docs/decisions.md.
#
# Also cleans up any leftover dnsmasq configuration from the old approach.
#
# Usage:
#   bin/setup-local-dns.sh                    # ENV=local (default)
#   ENV=prd bin/setup-local-dns.sh
#   ADGUARD_IP=192.168.122.201 NETWORK_SERVICE="Wi-Fi" bin/setup-local-dns.sh

set -e

ENV="${ENV:-local}"

info() { printf '\033[1;33m[info]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m     %s\n' "$*"; }
warn() { printf '\033[0;33m[warn]\033[0m   %s\n' "$*"; }
die()  { printf '\033[0;31m[error]\033[0m  %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FALLBACK_DNS="1.1.1.1"

# ---------------------------------------------------------------------------
# Resolve DOMAIN and NAMESPACE from values files
# ---------------------------------------------------------------------------

DEFAULT_DOMAIN="platypod.local"
DEFAULT_NAMESPACE="local-platypod"
[ "$ENV" = "prd" ] && DEFAULT_DOMAIN="platypod.ovh" && DEFAULT_NAMESPACE="prd-platypod"

# local's secrets moved off values/local/values.yaml into platypod-sops
# (SOPS-encrypted) — read the decrypted copy `make decrypt-secrets` produces
# instead, when present. prd still reads its NFS-symlinked values.yaml directly.
ENV_VALUES="$SCRIPT_DIR/tmp/secrets/$ENV.yaml"
[ -f "$ENV_VALUES" ] || ENV_VALUES="$SCRIPT_DIR/values/$ENV/values.yaml"

if [ -z "$DOMAIN" ] && command -v yq > /dev/null 2>&1; then
  DOMAIN="$(yq e '.traefik.domain' "$ENV_VALUES" 2>/dev/null || true)"
fi
DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"

if [ -z "$NAMESPACE" ] && command -v yq > /dev/null 2>&1; then
  NAMESPACE="$(yq e '.k8s.namespace' "$ENV_VALUES" 2>/dev/null || true)"
fi
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"

# ---------------------------------------------------------------------------
# Auto-detect Adguard IP
# ---------------------------------------------------------------------------
# local: MetalLB assigns a LoadBalancer IP. prod has no MetalLB (see
# ../infra/CLAUDE.md) — Adguard is exposed via Service externalIPs instead, so
# fall back to that when the LoadBalancer field is empty.

if [ -z "$ADGUARD_IP" ] && command -v kubectl > /dev/null 2>&1 && [ -n "$KUBECONFIG" ]; then
  info "Auto-detecting Adguard IP from cluster..."
  ADGUARD_IP="$(kubectl get svc adguard -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -z "$ADGUARD_IP" ]; then
    ADGUARD_IP="$(kubectl get svc adguard -n "$NAMESPACE" \
      -o jsonpath='{.spec.externalIPs[0]}' 2>/dev/null || true)"
  fi
  if [ -n "$ADGUARD_IP" ]; then
    info "Detected Adguard IP: ${ADGUARD_IP}"
  else
    info "Adguard service not found or no IP yet — enter manually."
  fi
fi

if [ -z "$ADGUARD_IP" ]; then
  printf 'Adguard LoadBalancer IP: '
  read -r ADGUARD_IP
fi
[ -n "$ADGUARD_IP" ] || die "ADGUARD_IP is required (security module not deployed/reconciled yet — check 'flux get helmreleases security -n \${ENV}-platypod')."

# ---------------------------------------------------------------------------
# Auto-detect active network service (e.g. "Wi-Fi", "Ethernet")
# ---------------------------------------------------------------------------

if [ -z "$NETWORK_SERVICE" ]; then
  DEFAULT_IFACE="$(route get default 2>/dev/null | awk '/interface:/{print $2}')"
  if [ -n "$DEFAULT_IFACE" ]; then
    NETWORK_SERVICE="$(networksetup -listallhardwareports 2>/dev/null \
      | awk -v dev="$DEFAULT_IFACE" '
          /Hardware Port:/ { port = substr($0, index($0,$3)) }
          /Device: / && $2 == dev { print port }
        ')"
  fi
fi

if [ -z "$NETWORK_SERVICE" ]; then
  info "Could not auto-detect network service. Common values: Wi-Fi, Ethernet"
  printf 'Network service name: '
  read -r NETWORK_SERVICE
fi
[ -n "$NETWORK_SERVICE" ] || die "NETWORK_SERVICE is required."
info "Network service: ${NETWORK_SERVICE}"

# ---------------------------------------------------------------------------
# Set system DNS: Adguard primary, 1.1.1.1 fallback
# ---------------------------------------------------------------------------

info "Setting system DNS to ${ADGUARD_IP} (primary) and ${FALLBACK_DNS} (fallback)..."
sudo networksetup -setdnsservers "$NETWORK_SERVICE" "$ADGUARD_IP" "$FALLBACK_DNS"
ok "System DNS set: ${ADGUARD_IP}, ${FALLBACK_DNS}"

# ---------------------------------------------------------------------------
# Remove /etc/resolver/DOMAIN — no longer needed (Adguard is system DNS now)
# ---------------------------------------------------------------------------

if [ -f "/etc/resolver/${DOMAIN}" ]; then
  sudo rm "/etc/resolver/${DOMAIN}"
  ok "Removed /etc/resolver/${DOMAIN} (superseded by system DNS)"
fi

# ---------------------------------------------------------------------------
# Clean up leftover dnsmasq entry if present
# ---------------------------------------------------------------------------

DNSMASQ_CONF="/opt/homebrew/etc/dnsmasq.conf"
if grep -q "address=/\.${DOMAIN}/" "$DNSMASQ_CONF" 2>/dev/null; then
  sed -i '' "/address=\/\.${DOMAIN}\//d" "$DNSMASQ_CONF"
  ok "Removed stale dnsmasq entry for .${DOMAIN}"
  if command -v brew > /dev/null 2>&1 && brew services list 2>/dev/null | grep -q "^dnsmasq.*started"; then
    sudo brew services restart dnsmasq
    info "dnsmasq restarted to pick up config change"
  fi
fi

# ---------------------------------------------------------------------------
# Flush DNS cache
# ---------------------------------------------------------------------------

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
ok "DNS cache flushed"

echo ""
ok "System DNS: ${ADGUARD_IP} (Adguard) → ${FALLBACK_DNS} (fallback)"
info "*.${DOMAIN} resolves via Adguard → Traefik (${ADGUARD_IP} rewrites to Traefik LB IP)."
info "When the cluster is suspended, internet DNS falls through to ${FALLBACK_DNS}."
info "*.${DOMAIN} will not resolve while the cluster is down — that's expected."
