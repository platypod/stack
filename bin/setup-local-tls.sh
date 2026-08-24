#!/bin/sh
# Install the mkcert local CA, generate a wildcard cert for *.DOMAIN, and
# store it as a Kubernetes TLS secret so Traefik can serve it.
#
# Run once per local machine, and again whenever the cert expires (~3 years).
# Requires: mkcert (auto-installed), kubectl in PATH, KUBECONFIG set.
#
# Usage:
#   bin/setup-local-tls.sh
#   DOMAIN=platypod.local NAMESPACE=local-platypod bin/setup-local-tls.sh

set -e

info() { printf '\033[1;33m[info]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m     %s\n' "$*"; }
die()  { printf '\033[0;31m[error]\033[0m  %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

# ---------------------------------------------------------------------------
# Resolve inputs from values files if not set in environment
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# DOMAIN/NAMESPACE default to local's actual values below — override via env
# if either ever needs to differ (values live in platypod-sops's
# clusters/local/secrets.enc.yaml now; sops -d it and pass DOMAIN=/NAMESPACE=
# explicitly if this ever needs to read them instead of the defaults).
DOMAIN="${DOMAIN:-platypod.local}"
NAMESPACE="${NAMESPACE:-local-platypod}"

SECRET_NAME="platypod-local-tls"
CERT_DIR="$(mktemp -d)"
trap 'rm -rf "$CERT_DIR"' EXIT

# ---------------------------------------------------------------------------
# Install mkcert if missing
# ---------------------------------------------------------------------------

if ! command -v mkcert > /dev/null 2>&1; then
  info "Installing mkcert via brew..."
  brew install mkcert
fi

# ---------------------------------------------------------------------------
# Trust the local CA in the macOS keychain (needs sudo — will prompt)
# ---------------------------------------------------------------------------

info "Trusting mkcert CA in macOS Keychain (may ask for your password)..."
mkcert -install
ok "mkcert CA trusted"

# ---------------------------------------------------------------------------
# Generate wildcard cert
# ---------------------------------------------------------------------------

info "Generating cert for *.${DOMAIN}..."
(cd "$CERT_DIR" && mkcert "*.${DOMAIN}")

CERT_FILE="$CERT_DIR/_wildcard.${DOMAIN}.pem"
KEY_FILE="$CERT_DIR/_wildcard.${DOMAIN}-key.pem"
[ -f "$CERT_FILE" ] || die "Cert file not found after mkcert — unexpected error."

# ---------------------------------------------------------------------------
# Ensure namespace exists
# ---------------------------------------------------------------------------

kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 \
  || kubectl create namespace "$NAMESPACE"

# ---------------------------------------------------------------------------
# Create or replace the K8s TLS secret
# ---------------------------------------------------------------------------

info "Storing cert as secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl create secret tls "$SECRET_NAME" \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

ok "Secret '$SECRET_NAME' ready in namespace '$NAMESPACE'"

# ---------------------------------------------------------------------------
# Publish the mkcert root CA as a ConfigMap so in-cluster clients that do TLS
# verification (e.g. BookStack's OIDC back-channel, which has no skip-verify
# option) can trust the self-signed wildcard cert Traefik serves. Containers
# don't trust the mkcert CA by default; charts mount this CM and run
# update-ca-certificates at startup. Local-only — prod uses real ACME certs.
# ---------------------------------------------------------------------------

CA_CM_NAME="mkcert-ca"
CA_ROOT="$(mkcert -CAROOT)"
CA_FILE="$CA_ROOT/rootCA.pem"
if [ -f "$CA_FILE" ]; then
  info "Publishing mkcert root CA as ConfigMap '$CA_CM_NAME'..."
  kubectl create configmap "$CA_CM_NAME" \
    --from-file=rootCA.pem="$CA_FILE" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml \
    | kubectl apply -f -
  ok "ConfigMap '$CA_CM_NAME' ready in namespace '$NAMESPACE'"
else
  info "mkcert root CA not found at $CA_FILE — skipping CA ConfigMap"
fi

ok "TLS cert valid for *.${DOMAIN} — expires in ~3 years (re-run this script to renew)"
