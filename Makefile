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

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Optional per-machine overrides (gitignored). On a fresh clone this file is
# absent → no-op. A machine that keeps the prod values.yaml on the NFS share sets
# STATE_MOUNT here so `make link-values` can symlink it. See
# ../infra/docs/secrets-on-nfs.md.
STATE_MOUNT ?=
-include $(ROOT)/Makefile.local

# REQUIRE_VALUES (set by Makefile.local for prd) makes deploy/diff abort if the
# env values.yaml is missing/dangling — e.g. the NFS share isn't mounted — rather
# than letting helmfile render a half-empty release from default values alone.
REQUIRE_VALUES ?=

.PHONY: require-values link-values
require-values:
	@if [ "$(REQUIRE_VALUES)" = "1" ] && [ ! -e "values/$(ENV)/values.yaml" ]; then \
	  echo "ERROR: values/$(ENV)/values.yaml is missing or dangling (NFS share not mounted?)."; \
	  echo "  Run 'make link-values ENV=$(ENV)' after mounting, or check the share is up."; \
	  echo "  Refusing to deploy from defaults only — secrets/overrides would be absent."; \
	  exit 1; \
	fi

link-values:   ## Symlink the env values.yaml to the NFS share  (ENV=prd)
	@test -n "$(STATE_MOUNT)" || { echo "STATE_MOUNT not set — configure Makefile.local first (see ../infra/docs/secrets-on-nfs.md)"; exit 1; }
	@target="$(STATE_MOUNT)/stack/$(ENV)/values.yaml"; \
	test -f "$$target" || { echo "Not found on share: $$target (mounted? copied?)"; exit 1; }; \
	ln -sfn "$$target" "values/$(ENV)/values.yaml" && \
	  echo "Linked values/$(ENV)/values.yaml -> $$target"

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

diff: require-values  ## Dry-run: show what would change  (ENV=dev MODULE=core)
	$(HELMFILE) $(SELECTOR) diff --args="--disable-validation"

deploy-base: require-values  ## Deploy always-on base only: persistence, core, security  (ENV=dev)
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--persistence sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--core sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--security sync

deploy: require-values  ## Deploy full stack or a single module  (ENV=dev MODULE=core)
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
ship-transcripts: ## [retired → prompt-meter submodule] Ship AI usage telemetry (ai_tx_* + transcripts). Delegates to ../prompt-meter; ARGS passed through.
	@echo "→ stack/bin/ship-transcripts is retired; delegating to the prompt-meter submodule (ai_tx_* schema)."
	@$(MAKE) --no-print-directory -C ../prompt-meter install >/dev/null
	@$(MAKE) --no-print-directory -C ../prompt-meter ship ARGS="$(ARGS)"

.PHONY: help
help:          ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
