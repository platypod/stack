# bin/

Convenience shell scripts, mostly wrapped by `make` targets — see
[../docs/make-targets.md](../docs/make-targets.md).

## Requirements

- [`helm`](https://helm.sh/docs/intro/install/)
- [`flux`](https://fluxcd.io/flux/installation/) — deploys are Git + Flux now
  (Helmfile retired, see [../docs/flux-migration.md](../docs/flux-migration.md))
- [`docker`](https://docs.docker.com/get-docker/) (for image builds only)

## build.sh — build and push a custom image to GHCR

```sh
bin/build.sh pokeclicker v0.10.25
bin/build.sh histube latest
bin/build.sh transmission-exporter arm64
```

Builds from `images/<name>/Dockerfile` and pushes to `ghcr.io/platypod/<name>:<version>`.
Requires docker authenticated to ghcr.io:
```sh
echo $GITHUB_TOKEN | docker login ghcr.io -u pittinic --password-stdin
```
