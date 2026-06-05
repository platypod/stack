#!/bin/sh
# Build and push a custom image to GHCR.
#
# Usage:
#   bin/build.sh <image> <version>
#
# Examples:
#   bin/build.sh pokeclicker v0.10.25
#   bin/build.sh histube latest
#   bin/build.sh transmission-exporter arm64
#
# Requirements: docker, authenticated to ghcr.io
#   echo $GITHUB_TOKEN | docker login ghcr.io -u <username> --password-stdin

set -e

REGISTRY="ghcr.io/pittinic"
IMAGE="$1"
VERSION="$2"

if [ -z "${IMAGE}" ] || [ -z "${VERSION}" ]; then
  echo "Usage: bin/build.sh <image> <version>"
  exit 1
fi

CONTEXT="images/${IMAGE}"
TAG="${REGISTRY}/${IMAGE}:${VERSION}"

if [ ! -d "${CONTEXT}" ]; then
  echo "Error: images/${IMAGE}/ not found"
  exit 1
fi

echo ">>> Building ${TAG}"
docker build \
  --build-arg VERSION="${VERSION}" \
  --platform linux/arm64 \
  -t "${TAG}" \
  "${CONTEXT}"

echo ">>> Pushing ${TAG}"
docker push "${TAG}"

echo ">>> Done: ${TAG}"
