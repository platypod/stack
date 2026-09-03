# traefik (core)

The cluster ingress controller — terminates TLS, routes every `IngressRoute`, and
exposes metrics + a dashboard. Reached via a MetalLB `LoadBalancer`.

- **Image:** pinned via `traefik.image.tag` (no `latest`). Init container `busybox:1`
  fixes `acme.json` permissions before Traefik starts.
- **Ports:** http `80` (nodePort 30680), https `443` (nodePort 30679), dashboard
  `9999` (label `traefik-dashboard`, scraped by the collector for the Services
  dashboard), `ldaps` `636` (TCP entrypoint, not HTTP — fronts LLDAP for
  clients outside the cluster; see [../security/lldap.md](../security/lldap.md)).
  Always present; only actually routed when `lldap.ldaps.enable`.
- **LoadBalancer IP:** `traefik.loadBalancerIP` (set per env) — also consumed by the
  AdGuard DNS rewrite so `*.platypod.ovh` resolves to Traefik internally.

## TLS / ACME
- `acme.enable` is a **master gate**: when false the resolver is never loaded and
  `acme.json` stays mode 660 → self-signed/default cert, zero Let's Encrypt traffic
  (safe default; flip on only after a staging test).
- **Staging vs prod:** `acme.endpoint` + `acme.storage` are separated so a staging
  run never clobbers the prod account/certs. Switch endpoint→prod and
  storage→`acme.json` once verified.
- **Prod:** real Let's Encrypt **wildcard `*.platypod.ovh` via OVH DNS-01**
  (`resolverName: letsencrypt`, provider `ovh`, `OVH_*` creds) — no inbound needed,
  sidesteps the host forwarder. Browser-trusted.
- `tls.selfSigned` / `tls.wildcard` / `tls.secretName` cover the dev (mkcert) path.

## Gotchas
- `acme.json` must be mode 600 or Traefik refuses it — the init container enforces it.
- Public-stack reachability depends on the host nginx ingress + socket_vmnet; after a
  router reboot use `make rearm-ingress` (infra) — see
  [infra/docs/troubleshooting.md](../../../infra/docs/troubleshooting.md).
- **DNS-01 needs a real wildcard A record, not a wildcard CNAME to the apex.** A
  `*.platypod.ovh → platypod.ovh` CNAME swallows the `_acme-challenge.*` TXT lookup
  DNS-01 depends on — use a wildcard **A** record instead. CoreDNS also caches the
  old CNAME after the DNS change; `kubectl -n kube-system rollout restart
  deploy/coredns` if a fix isn't taking effect.
- **Enabling the ACME resolver (fixing `acme.json` perms to 600) must be gated
  behind a values flag, never unconditional.** Once enabled, Traefik immediately
  orders certs for every host it knows about; any host not already covered by a
  cached cert needs real public reachability (DNS + router forwarding) or its
  order fails-loops straight into Let's Encrypt's "failed authorizations per
  hostname per hour" limit (5/h) — recoverable (hourly), but avoidable. Sequence:
  wire reachability (or use DNS-01, which needs none), test on LE **staging**
  first, then flip to production ACME in one controlled move. Also re-check
  `git status`/working-tree diff before pushing any commit that touches Traefik
  — the push *is* the deploy now, so an unrelated staged change ships alongside
  it with nothing in between to catch it.
