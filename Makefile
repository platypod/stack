ENV    ?= dev
MODULE ?=

# Always point at the kubeconfig written by ../infra,
# ignoring any KUBECONFIG already set in the shell (e.g. OrbStack).
# Command-line override still works: make deploy KUBECONFIG=/other/path
#
# Services use env names dev/prd, but infra writes its kubeconfigs under
# dev/prod — and prod is only reachable through the SSH tunnel, so it needs the
# `kubeconfig-tunnel` file. Map service env -> infra kubeconfig path explicitly.
GENERATED   := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/../infra/.generated
KUBECONFIG_dev := $(GENERATED)/dev/kubeconfig
KUBECONFIG_prd := $(GENERATED)/prod/kubeconfig-tunnel
export KUBECONFIG := $(KUBECONFIG_$(ENV))

HELMFILE = helmfile --environment $(ENV)
SELECTOR = $(if $(MODULE),--selector name=$(ENV)--platypod--$(MODULE),)

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

.PHONY: install-deps check-deps
install-deps:  ## Install required tools (helm, helmfile, kubectl)
	sh bin/install-deps.sh

check-deps:    ## Check which tools are installed without installing anything
	sh bin/install-deps.sh --check

# ---------------------------------------------------------------------------
# Local dev setup (macOS)
# ---------------------------------------------------------------------------

.PHONY: setup-dev-tls setup-dev-dns setup-dev

setup-dev-tls:  ## Trust mkcert CA + create/refresh wildcard TLS secret in the cluster
	@sh bin/setup-dev-tls.sh

setup-dev-dns:  ## Set system DNS to Adguard (primary) + 1.1.1.1 (fallback); clean up dnsmasq
	@sh bin/setup-dev-dns.sh

setup-dev: setup-dev-tls install-crds  ## Full dev bootstrap: TLS, CRDs, base deploy, DNS
	@$(MAKE) --no-print-directory deploy-base
	@$(MAKE) --no-print-directory setup-dev-dns

# ---------------------------------------------------------------------------
# Cluster bootstrap
# ---------------------------------------------------------------------------

TRAEFIK_VERSION ?= v3.5
CSI_DRIVER_NFS_VERSION ?= 4.13.2

.PHONY: install-crds install-csi
install-crds:  ## Install Traefik CRDs on the cluster (TRAEFIK_VERSION=v3.5)
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml

install-csi:   ## Install the NFS CSI driver (nfs.csi.k8s.io) — required for NFS-backed prod storage
	helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
	helm repo update csi-driver-nfs
	helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
	  --namespace kube-system --version $(CSI_DRIVER_NFS_VERSION) --wait

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

.PHONY: diff deploy deploy-base destroy

status:        ## List deployed releases and their status  (ENV=dev)
	helm list --namespace $(ENV)-platypod

diff:          ## Dry-run: show what would change  (ENV=dev MODULE=core)
	$(HELMFILE) $(SELECTOR) diff --args="--disable-validation"

deploy-base:   ## Deploy always-on base only: persistence, core, security  (ENV=dev)
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--persistence sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--core sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--security sync

deploy:        ## Deploy full stack or a single module  (ENV=dev MODULE=core)
	$(HELMFILE) $(SELECTOR) sync --args="--timeout 10m0s"

destroy:       ## Destroy full stack or a single module  (ENV=dev MODULE=core)
	$(HELMFILE) $(SELECTOR) destroy

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

.PHONY: build
build:         ## Build and push a custom image  (IMAGE=pokeclicker VERSION=v0.10.25)
	sh bin/build.sh $(IMAGE) $(VERSION)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

.PHONY: ship-transcripts
ship-transcripts: ## Ship Claude Code transcripts → Loki (content) + Mimir (claude_tx_* metrics); redacts stack/values secrets; tails by default. ARGS="--dry-run|--limit N|--reset|--insecure|--projects=GLOB" (env: OTEL_EXPORTER_OTLP_ENDPOINT, PLATYPOD_TRANSCRIPT_STATE)
	@test -x bin/.venv/bin/python || { echo "bootstrapping bin/.venv…"; python3 -m venv bin/.venv && bin/.venv/bin/pip install -q --disable-pip-version-check opentelemetry-sdk opentelemetry-exporter-otlp-proto-grpc; }
	@bin/.venv/bin/python bin/ship-transcripts $(ARGS)

.PHONY: help
help:          ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
