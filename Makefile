ENV    ?= dev
MODULE ?=

# Always point at the kubeconfig written by infra-as-code/k8s-in-vms,
# ignoring any KUBECONFIG already set in the shell (e.g. OrbStack).
# Command-line override still works: make deploy KUBECONFIG=/other/path
export KUBECONFIG := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/../infra-as-code/k8s-in-vms/.generated/$(ENV)/kubeconfig

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

setup-dev-dns:  ## Configure dnsmasq for *.platypod.local → Traefik LB IP (auto-detected)
	@sh bin/setup-dev-dns.sh

setup-dev: setup-dev-tls install-crds  ## Full dev bootstrap: TLS, CRDs, base deploy, DNS
	@$(MAKE) --no-print-directory deploy-base
	@$(MAKE) --no-print-directory setup-dev-dns

# ---------------------------------------------------------------------------
# Cluster bootstrap
# ---------------------------------------------------------------------------

TRAEFIK_VERSION ?= v3.5

.PHONY: install-crds
install-crds:  ## Install Traefik CRDs on the cluster (TRAEFIK_VERSION=v3.5)
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
	kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml

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
	$(HELMFILE) $(SELECTOR) sync

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

.PHONY: help
help:          ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
