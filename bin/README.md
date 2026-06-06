# bin/

Convenience shell scripts. Source them to get the functions.

## Requirements

- [`helmfile`](https://helmfile.readthedocs.io/en/latest/#installation)
- [`helm`](https://helm.sh/docs/intro/install/)
- [`docker`](https://docs.docker.com/get-docker/) (for image builds only)

## helm.sh — deploy/destroy wrappers

```sh
. bin/helm.sh

deploy --env dev              # deploy full stack
deploy --env dev --dry-run    # diff only
deploy_one --env dev --module core

destroy --env dev             # uninstall full stack
destroy_one --env dev --module core
```

Default env is `dev` (override with `PLATYPOD__HELM__DEFAULT_ENV`).

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
