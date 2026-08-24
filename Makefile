ENV    ?= local
MODULE ?=

# Always point at the kubeconfig written by ../infra,
# ignoring any KUBECONFIG already set in the shell (e.g. OrbStack).
# Command-line override still works: make status KUBECONFIG=/other/path
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

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Optional per-machine overrides (gitignored). On a fresh clone this file is
# absent → no-op. Only used today to set STATE_MOUNT for setup-age-key's
# SOPS age key NFS backup — see Makefile.local.example.
STATE_MOUNT ?=
-include $(ROOT)/Makefile.local

# SOPS_AGE_KEY_FILE: where `sops` finds the local age private key (see
# ../platypod-sops, stack/docs/flux-migration.md). Not settable via
# Makefile.local on purpose — every machine that decrypts uses the same
# default path (age key is backed up on the NFS share, restored there).
SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE

# Restores the age key from the NFS backup (STATE_MOUNT/sops-age-key.txt, set
# in Makefile.local — see Makefile.local.example) if present; otherwise
# generates a fresh one and prints the backup step, so a rebuilt/new machine
# never has to be told this by hand. Safe to re-run: no-ops if the key file
# already exists.
.PHONY: setup-age-key
setup-age-key: ## Restore the SOPS age key from NFS, or generate + back it up (first-ever setup only)
	@if [ -f "$(SOPS_AGE_KEY_FILE)" ]; then \
	  echo "Age key already present at $(SOPS_AGE_KEY_FILE) — nothing to do."; \
	elif [ -n "$(STATE_MOUNT)" ] && [ -f "$(STATE_MOUNT)/sops-age-key.txt" ]; then \
	  mkdir -p "$(dir $(SOPS_AGE_KEY_FILE))" && \
	  cp "$(STATE_MOUNT)/sops-age-key.txt" "$(SOPS_AGE_KEY_FILE)" && \
	  chmod 600 "$(SOPS_AGE_KEY_FILE)" && \
	  echo "Restored age key from $(STATE_MOUNT)/sops-age-key.txt -> $(SOPS_AGE_KEY_FILE)"; \
	elif [ -z "$(STATE_MOUNT)" ]; then \
	  echo "ERROR: STATE_MOUNT not set — configure Makefile.local first (see Makefile.local.example)."; \
	  echo "  Needed to check for an existing age key backup before generating a new"; \
	  echo "  one — a new key can't decrypt anything already in platypod-sops."; \
	  exit 1; \
	else \
	  echo "No backup found at $(STATE_MOUNT)/sops-age-key.txt — generating a NEW key"; \
	  echo "(first-ever setup only; if platypod-sops already has encrypted secrets," ; \
	  echo " STOP and find the real backup instead, or every secret must be re-encrypted)."; \
	  mkdir -p "$(dir $(SOPS_AGE_KEY_FILE))" && \
	  age-keygen -o "$(SOPS_AGE_KEY_FILE)" && \
	  chmod 600 "$(SOPS_AGE_KEY_FILE)" && \
	  cp "$(SOPS_AGE_KEY_FILE)" "$(STATE_MOUNT)/sops-age-key.txt" && \
	  chmod 600 "$(STATE_MOUNT)/sops-age-key.txt" && \
	  echo "Generated + backed up to $(STATE_MOUNT)/sops-age-key.txt"; \
	fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

.PHONY: install-deps check-deps
install-deps:  ## Install required tools (kubectl, helm, flux, sops, age)
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

# Post-Helmfile (Phase 8): Flux itself deploys all 8 modules once
# bootstrapped, ordered by each HelmRelease's dependsOn — no more manual
# "base only" staging. flux-bootstrap creates the flux-system namespace;
# flux-sops-secrets needs it to exist first, so bootstrap runs before it.
# setup-local-dns needs AdGuard's LoadBalancer IP, which only exists once
# the `apps` Kustomization has actually reconciled — force that explicitly
# rather than relying on its next poll interval (up to 10m otherwise).
# NOTE: this sequence hasn't been exercised end-to-end since Phase 8 — the
# only rebuild that happened this migration predates it (Phase 3).
setup-local: setup-age-key setup-local-tls install-crds  ## Full local bootstrap: age key, TLS, CRDs, Flux (all 8 modules), DNS
	@$(MAKE) --no-print-directory flux-bootstrap ENV=local
	@$(MAKE) --no-print-directory flux-sops-secrets ENV=local
	@flux reconcile kustomization apps -n flux-system --timeout=5m || \
	  flux reconcile kustomization apps -n flux-system --timeout=5m
	@$(MAKE) --no-print-directory setup-local-dns

# ---------------------------------------------------------------------------
# Cluster bootstrap
# ---------------------------------------------------------------------------

TRAEFIK_VERSION ?= v3.5
CSI_DRIVER_NFS_VERSION ?= 4.13.2

# Traefik CRDs are vendored into infrastructure/crds/ (Flux's kustomize-
# controller has no network access, so it can't fetch these live — see
# docs/flux-migration.md gotcha 1). vendor-crds refreshes the vendored copy
# from upstream (re-run when bumping TRAEFIK_VERSION); install-crds applies
# that same vendored copy imperatively — one source of truth for both the
# imperative and Flux-managed paths, and cluster bootstrap no longer depends
# on raw.githubusercontent.com being reachable.
#
# There is deliberately no install-csi target anymore. csi-driver-nfs is
# Flux-managed (infrastructure/csi/, prod-only) since Phase 7 — re-running
# an imperative `helm upgrade --install csi-driver-nfs ...` under the OLD
# release name would recreate the exact ownership-conflict bug fixed in
# docs/flux-migration.md gotcha 14 (a HelmRelease with no matching
# releaseName silently takes over the live Deployment/DaemonSet from
# whichever release installed it, imperative or not).
.PHONY: vendor-crds install-crds
vendor-crds:   ## Re-fetch the vendored Traefik CRDs from upstream (TRAEFIK_VERSION=v3.5)
	curl -fsSL https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml -o infrastructure/crds/traefik-crds.yaml
	curl -fsSL https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml -o infrastructure/crds/traefik-rbac.yaml
	@echo "Vendored Traefik $(TRAEFIK_VERSION) CRDs -> infrastructure/crds/. Review the diff and commit."

install-crds:  ## Apply the vendored Traefik CRDs to the cluster
	kubectl apply -k infrastructure/crds/

# Idempotent — safe to re-run (e.g. after rotating the deploy key, or to pick
# up a new flux version). Adds a read-only deploy key to platypod/stack and
# pushes clusters/$(ENV)/flux-system/* to main if not already present. Needs
# `gh` authenticated (uses `gh auth token`) — see docs/flux-migration.md
# Phase 3.
#
# image-reflector-controller/image-automation-controller only on local —
# they're driven by pushing to main, which only local tracks continuously;
# prd stays tag-gated and doesn't need them running idle. See Phase 9.
COMPONENTS_EXTRA_local := --components-extra=image-reflector-controller,image-automation-controller
COMPONENTS_EXTRA_prd   :=
.PHONY: flux-bootstrap
flux-bootstrap: ## Bootstrap/reconcile Flux against clusters/$(ENV) (ENV=local)
	GITHUB_TOKEN="$$(gh auth token)" flux bootstrap github \
	  --owner=platypod \
	  --repository=stack \
	  --path=clusters/$(ENV) \
	  --branch=main \
	  --personal \
	  $(COMPONENTS_EXTRA_$(ENV))

# Idempotent — safe to re-run. Creates the in-cluster deploy key +
# decryption secret the platypod-sops GitRepository/Kustomization
# (clusters/$(ENV)/secrets.yaml) need: a read-only deploy key on
# platypod/platypod-sops (one per cluster, since a GitRepository's
# secretRef is scoped to that cluster alone), and the sops-age Secret
# holding the local age private key so kustomize-controller can decrypt
# secrets.enc.yaml. Was done ad-hoc in the terminal for local (twice,
# flagged both times) — scripted now per docs/flux-migration.md Phase 7.
.PHONY: flux-sops-secrets
flux-sops-secrets: ## Create in-cluster deploy key + sops-age Secret for platypod-sops (ENV=local|prd)
	@if kubectl get secret platypod-sops-deploy-key -n flux-system >/dev/null 2>&1; then \
	  echo "platypod-sops-deploy-key already exists — skipping (delete it first to rotate)."; \
	else \
	  flux create secret git platypod-sops-deploy-key \
	    --namespace=flux-system \
	    --url=ssh://git@github.com/platypod/platypod-sops \
	    --export > /tmp/platypod-sops-deploy-key.yaml && \
	  kubectl apply -f /tmp/platypod-sops-deploy-key.yaml && \
	  yq '.stringData."identity.pub"' /tmp/platypod-sops-deploy-key.yaml > /tmp/platypod-sops-deploy-key.pub && \
	  gh repo deploy-key add /tmp/platypod-sops-deploy-key.pub \
	    --repo platypod/platypod-sops --title "flux-system ($(ENV))" && \
	  rm /tmp/platypod-sops-deploy-key.yaml /tmp/platypod-sops-deploy-key.pub; \
	fi
	@if kubectl get secret sops-age -n flux-system >/dev/null 2>&1; then \
	  echo "sops-age secret already exists — skipping."; \
	else \
	  kubectl create secret generic sops-age --namespace=flux-system \
	    --from-file=age.agekey=$(SOPS_AGE_KEY_FILE); \
	fi

# Idempotent — safe to re-run. Creates a SEPARATE, read-write deploy key on
# platypod/stack, used only by the stack-image-automation GitRepository
# (clusters/local/image-automation.yaml) — deliberately not the same
# credential flux-system's primary sync GitRepository uses, which stays
# read-only. The first read-write credential this migration has created;
# see docs/flux-migration.md Phase 9 for why it's scoped this narrowly.
.PHONY: image-automation-deploy-key
image-automation-deploy-key: ## Create a read-write deploy key for image-automation-controller's own GitRepository (ENV=local)
	@if kubectl get secret stack-image-automation-deploy-key -n flux-system >/dev/null 2>&1; then \
	  echo "stack-image-automation-deploy-key already exists — skipping (delete it first to rotate)."; \
	else \
	  flux create secret git stack-image-automation-deploy-key \
	    --namespace=flux-system \
	    --url=ssh://git@github.com/platypod/stack \
	    --export > /tmp/stack-image-automation-deploy-key.yaml && \
	  kubectl apply -f /tmp/stack-image-automation-deploy-key.yaml && \
	  yq '.stringData."identity.pub"' /tmp/stack-image-automation-deploy-key.yaml > /tmp/stack-image-automation-deploy-key.pub && \
	  gh repo deploy-key add /tmp/stack-image-automation-deploy-key.pub \
	    --repo platypod/stack --title "image-automation ($(ENV))" --allow-write && \
	  rm /tmp/stack-image-automation-deploy-key.yaml /tmp/stack-image-automation-deploy-key.pub; \
	fi

# ---------------------------------------------------------------------------
# Deployment — via Git + Flux, not this Makefile. See docs/operations.md.
# `flux get helmreleases -n <env>-platypod` / `flux reconcile helmrelease
# <module> -n <env>-platypod` are the day-to-day equivalents of the old
# `make diff`/`make deploy`.
# ---------------------------------------------------------------------------

status:        ## List deployed Helm releases and their status  (ENV=local)
	helm list --namespace $(ENV)-platypod

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
