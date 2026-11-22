#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
IMAGE_NAME="ravios-chromium:latest"
ARTIFACT_DIR="$ROOT_DIR/artifacts/ravios-chromium/image"
IMAGE_TAR="$ARTIFACT_DIR/ravios-chromium.tar"

cd "$ROOT_DIR"

mkdir -p "$ARTIFACT_DIR"

echo "Building $IMAGE_NAME ..."
docker build -t "$IMAGE_NAME" -f docker/chromium/Dockerfile docker/chromium

echo
echo "Saving image to $IMAGE_TAR ..."
docker save "$IMAGE_NAME" -o "$IMAGE_TAR"
test -s "$IMAGE_TAR"

echo
echo "Image size:"
docker images "$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
echo "Tar size: $(du -h "$IMAGE_TAR" | cut -f1)"
echo
echo "Done. The Buildroot post-build hook copies this artifact into the target rootfs."
