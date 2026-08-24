#!/bin/sh
# Install all tools required to build and deploy platypod.
#
# Supported package managers (in order of preference):
#   macOS  : brew
#   Linux  : apt-get, then direct binary download as fallback
#
# Usage:
#   bin/install-deps.sh           # install everything
#   bin/install-deps.sh --check   # only check what is / isn't installed

set -e

CHECK_ONLY=0
[ "$1" = "--check" ] && CHECK_ONLY=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()      { printf "${GREEN}[ok]${NC}     %s\n" "$*"; }
missing() { printf "${RED}[missing]${NC} %s\n" "$*"; }
info()    { printf "${YELLOW}[info]${NC}   %s\n" "$*"; }

has() { command -v "$1" > /dev/null 2>&1; }

check() {
  local cmd="$1" hint="$2"
  if has "${cmd}"; then
    ok "${cmd}  ($(${cmd} version --short 2>/dev/null || ${cmd} --version 2>/dev/null | head -1))"
    return 0
  else
    missing "${cmd}  — ${hint}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Install via brew (macOS)
# ---------------------------------------------------------------------------

brew_install() {
  local pkg="$1"
  info "brew install ${pkg}"
  brew install "${pkg}"
}

# ---------------------------------------------------------------------------
# Install helm binary directly (Linux fallback)
# ---------------------------------------------------------------------------

install_helm_linux() {
  info "Installing helm via get-helm-3 script"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sh
}

# ---------------------------------------------------------------------------
# Install sops binary directly (Linux fallback)
# ---------------------------------------------------------------------------

SOPS_VERSION="3.13.3"

install_sops_linux() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac
  local url="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${arch}"
  info "Downloading sops v${SOPS_VERSION} for linux/${arch}"
  curl -fsSL "${url}" -o /usr/local/bin/sops
  chmod +x /usr/local/bin/sops
}

# ---------------------------------------------------------------------------
# Install age binary directly (Linux fallback)
# ---------------------------------------------------------------------------

AGE_VERSION="1.3.1"

install_age_linux() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac
  local url="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${arch}.tar.gz"
  info "Downloading age v${AGE_VERSION} for linux/${arch}"
  curl -fsSL "${url}" | tar -xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen
  chmod +x /usr/local/bin/age /usr/local/bin/age-keygen
}

# ---------------------------------------------------------------------------
# Install flux binary directly (Linux fallback)
# ---------------------------------------------------------------------------

FLUX_VERSION="2.9.4"

install_flux_linux() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac
  local url="https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${arch}.tar.gz"
  info "Downloading flux v${FLUX_VERSION} for linux/${arch}"
  curl -fsSL "${url}" | tar -xz -C /usr/local/bin flux
  chmod +x /usr/local/bin/flux
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "=== platypod dependency check ==="
echo ""

ALL_OK=1

check kubectl   "https://kubernetes.io/docs/tasks/tools/"       || ALL_OK=0
check helm      "https://helm.sh/docs/intro/install/"           || ALL_OK=0
check sops      "https://github.com/getsops/sops#download"      || ALL_OK=0
check age       "https://github.com/FiloSottile/age#installation" || ALL_OK=0
check flux      "https://fluxcd.io/flux/installation/"           || ALL_OK=0
check docker    "https://docs.docker.com/get-docker/ (only needed to build custom images)" || true  # optional

echo ""

if [ "${CHECK_ONLY}" = "1" ]; then
  [ "${ALL_OK}" = "1" ] && ok "All required tools present" || info "Some tools are missing — run without --check to install"
  exit 0
fi

if [ "${ALL_OK}" = "1" ]; then
  ok "All required tools already installed — nothing to do"
  exit 0
fi

# Install missing tools
OS="$(uname -s)"

if [ "${OS}" = "Darwin" ]; then
  has brew || { missing "brew not found — install from https://brew.sh first"; exit 1; }
  has kubectl  || brew_install kubectl
  has helm     || brew_install helm
  has sops     || brew_install sops
  has age      || brew_install age
  has flux     || brew_install fluxcd/tap/flux
elif [ "${OS}" = "Linux" ]; then
  if has apt-get; then
    has kubectl || {
      info "Installing kubectl via apt"
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' \
        | tee /etc/apt/sources.list.d/kubernetes.list
      apt-get update -q && apt-get install -y kubectl
    }
  fi
  has helm     || install_helm_linux
  has sops     || install_sops_linux
  has age      || install_age_linux
  has flux     || install_flux_linux
else
  missing "Unsupported OS: ${OS} — please install tools manually"
  exit 1
fi

echo ""
echo "=== Verifying after install ==="
echo ""
check kubectl  ""
check helm     ""
check sops     ""
check age      ""
check flux     ""
