ENV    ?= local
MODULE ?=

# Always point at the kubeconfig written by ../infra,
# ignoring any KUBECONFIG already set in the shell (e.g. OrbStack).
# Command-line override still works: make deploy KUBECONFIG=/other/path
#
# Services use env names local/prd, but infra writes its kubeconfigs under
# local/prod. Map service env -> infra kubeconfig path explicitly.
#
# prd's control plane is bare metal on the LAN (chuwi-cp1), directly reachable
# at https://k8s.platypod.lan:6443 — the generated kubeconfig works as-is.
# Before the 2026-07-30 cutover the control plane was a vfkit guest reachable
# only from its VM host, which is why this pointed at an SSH-tunnel copy
# (`kubeconfig-tunnel`); that tunnel is retired, see
# ../infra/docs/baremetal-cp-migration.md.
GENERATED   := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/../infra/.generated
KUBECONFIG_local := $(GENERATED)/local/kubeconfig
KUBECONFIG_prd := $(GENERATED)/prod/kubeconfig
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

# SOPS_AGE_KEY_FILE: where `sops` finds the local age private key (see
# ../platypod-sops, stack/docs/flux-migration.md). Not settable via
# Makefile.local on purpose — every machine that decrypts uses the same
# default path (age key is backed up on the NFS share, restored there).
SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE

# ../platypod-sops/stack/<env>/secrets.enc.yaml -> tmp/secrets/<env>.yaml.
# Direct `sops -d`, not helmfile's native `secrets:` stanza — the
# helm-secrets plugin it shells out to is currently broken on Helm v4 (see
# helmfile.yaml.gotmpl). No-ops for envs with no secrets.enc.yaml yet (prd,
# pre-migration).
.PHONY: decrypt-secrets
decrypt-secrets:
	@src="../platypod-sops/stack/$(ENV)/secrets.enc.yaml"; \
	if [ -f "$$src" ]; then \
	  mkdir -p tmp/secrets && \
	  sops -d "$$src" > "tmp/secrets/$(ENV).yaml" && \
	  echo "Decrypted $$src -> tmp/secrets/$(ENV).yaml"; \
	fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

.PHONY: install-deps check-deps
install-deps:  ## Install required tools (helm, helmfile, kubectl)
	sh bin/install-deps.sh

check-deps:    ## Check which tools are installed without installing anything
	sh bin/install-deps.sh --check

# ---------------------------------------------------------------------------
# Local machine setup (macOS)
# ---------------------------------------------------------------------------

.PHONY: setup-local-tls setup-local-dns setup-prod-dns setup-local

setup-local-tls:  ## Trust mkcert CA + create/refresh wildcard TLS secret in the cluster
	@sh bin/setup-local-tls.sh

setup-local-dns:  ## Set system DNS to Adguard (primary) + 1.1.1.1 (fallback); clean up dnsmasq
	@sh bin/setup-local-dns.sh

# Same script, prod's Adguard/domain/namespace/kubeconfig. Keep a manual
# /etc/hosts entry for k8s.platypod.lan too (see bin/setup-local-dns.sh) — if
# Adguard itself is ever down, that's the only way kubectl still resolves the
# API to fix it.
setup-prod-dns:  ## Set system DNS to Adguard (prod) + 1.1.1.1 (fallback)
	@KUBECONFIG=$(KUBECONFIG_prd) ENV=prd sh bin/setup-local-dns.sh

setup-local: setup-local-tls install-crds  ## Full local bootstrap: TLS, CRDs, base deploy, DNS
	@$(MAKE) --no-print-directory deploy-base
	@$(MAKE) --no-print-directory setup-local-dns

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

status:        ## List deployed releases and their status  (ENV=local)
	helm list --namespace $(ENV)-platypod

diff: require-values decrypt-secrets  ## Dry-run: show what would change  (ENV=local MODULE=core)
	$(HELMFILE) $(SELECTOR) diff --args="--disable-validation"

deploy-base: require-values decrypt-secrets  ## Deploy always-on base only: persistence, core, security  (ENV=local)
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--persistence sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--core sync
	@helmfile --environment $(ENV) --selector name=$(ENV)--platypod--security sync

deploy: require-values decrypt-secrets  ## Deploy full stack or a single module  (ENV=local MODULE=core)
	$(HELMFILE) $(SELECTOR) sync --args="--timeout 10m0s"

destroy:       ## Destroy full stack or a single module  (ENV=local MODULE=core)
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

# ---------------------------------------------------------------------------
# Headroom proxy (dev-tools module)
# ---------------------------------------------------------------------------

# Mirrors the local/prd domains (local's now in platypod-sops, prd's in
# values/prd/values.yaml).
DOMAIN_local := platypod.local
DOMAIN_prd := platypod.ovh

.PHONY: proxy-on proxy-off
proxy-on:      ## Route Claude Code (terminal + Desktop) through the Headroom proxy: sets ANTHROPIC_BASE_URL in ~/.claude/settings.json  (ENV=local)
	@sh bin/set-claude-proxy.sh on https://headroom.$(DOMAIN_$(ENV))

proxy-off:     ## Stop routing through the Headroom proxy: removes ANTHROPIC_BASE_URL from ~/.claude/settings.json
	@sh bin/set-claude-proxy.sh off

.PHONY: help
help:          ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
