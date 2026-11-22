#!/bin/sh

set -e

BOARD_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$BOARD_DIR/../../../.." && pwd)"

# ------------------------------------------------------------
# Embed offline Chromium Docker image
# ------------------------------------------------------------

CHROMIUM_IMAGE_TAR="$PROJECT_ROOT/artifacts/ravios-chromium/image/ravios-chromium.tar"
CHROMIUM_TARGET_DIR="$TARGET_DIR/usr/share/ravios/docker-images"
CHROMIUM_TARGET_TAR="$CHROMIUM_TARGET_DIR/ravios-chromium.tar"

if [ ! -s "$CHROMIUM_IMAGE_TAR" ]; then
    echo "ERROR: Chromium Docker image artifact is missing or empty: $CHROMIUM_IMAGE_TAR" >&2
    echo "Run docker/chromium/prepare-image.ps1 before building RaviOS." >&2
    exit 1
fi

mkdir -p "$CHROMIUM_TARGET_DIR"
install -m 0644 "$CHROMIUM_IMAGE_TAR" "$CHROMIUM_TARGET_TAR"

echo "Embedded Chromium image: $CHROMIUM_IMAGE_TAR -> $CHROMIUM_TARGET_TAR"

# ------------------------------------------------------------
# Embed offline Ollama image and Qwen model
# ------------------------------------------------------------

echo "===== Installing offline Ollama bundle ====="

BUNDLE_DIR="$PROJECT_ROOT/artifacts/ollama-bundle"
OFFLINE_DIR="$TARGET_DIR/usr/share/ravios/offline/ollama"

IMAGE_ARCHIVE="$BUNDLE_DIR/image/ravi-ollama-image.tar"
MODEL_ARCHIVE="$BUNDLE_DIR/models/qwen2.5-0.5b.tar"

test -s "$IMAGE_ARCHIVE" || {
    echo "ERROR: Ollama image archive is missing or empty: $IMAGE_ARCHIVE" >&2
    exit 1
}

test -s "$MODEL_ARCHIVE" || {
    echo "ERROR: Qwen model archive is missing or empty: $MODEL_ARCHIVE" >&2
    exit 1
}

mkdir -p "$OFFLINE_DIR/image" "$OFFLINE_DIR/models"

install -m 0644 "$IMAGE_ARCHIVE" \
    "$OFFLINE_DIR/image/ravi-ollama-image.tar"

install -m 0644 "$MODEL_ARCHIVE" \
    "$OFFLINE_DIR/models/qwen2.5-0.5b.tar"

echo "Offline Ollama bundle installed successfully."

# ------------------------------------------------------------
# Set executable permissions
# ------------------------------------------------------------

chmod 0755 "$TARGET_DIR/etc/init.d/S50docker-data"
chmod 0755 "$TARGET_DIR/etc/init.d/S60dockerd"
chmod 0755 "$TARGET_DIR/etc/init.d/S70ravios-chromium-image"
chmod 0755 "$TARGET_DIR/etc/init.d/S70ollama"
chmod 0755 "$TARGET_DIR/usr/sbin/ravios-docker-data"
chmod 0755 "$TARGET_DIR/usr/bin/ravios-session"
chmod 0755 "$TARGET_DIR/etc/ravios/session.d/"*.sh 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/init.d/S90ravios-session"
chmod 0755 "$TARGET_DIR/etc/profile.d/10-locale.sh"