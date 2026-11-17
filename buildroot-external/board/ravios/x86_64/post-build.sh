#!/bin/sh

set -e

BOARD_DIR="$(dirname "$0")"

cp -f "$BOARD_DIR/grub-bios.cfg" \
    "$TARGET_DIR/boot/grub/grub.cfg"

cp -f "$TARGET_DIR/lib/grub/i386-pc/boot.img" \
    "$BINARIES_DIR/boot.img"

chmod 0755 "$TARGET_DIR/etc/init.d/S50docker-data"
chmod 0755 "$TARGET_DIR/etc/init.d/S60dockerd"
chmod 0755 "$TARGET_DIR/etc/init.d/S70ollama"
chmod 0755 "$TARGET_DIR/usr/sbin/ravios-docker-data"

echo "===== Installing offline Ollama bundle ====="

BUNDLE_DIR="/workspace/artifacts/ollama-bundle"
OFFLINE_DIR="$TARGET_DIR/usr/share/ravios/offline/ollama"

IMAGE_ARCHIVE="$BUNDLE_DIR/image/ravi-ollama-image.tar"
MODEL_ARCHIVE="$BUNDLE_DIR/models/qwen2.5-0.5b.tar"

test -s "$IMAGE_ARCHIVE" || {
    echo "Error: Ollama Image archive not found." >&2
    exit 1
}

test -s "$MODEL_ARCHIVE" || {
    echo "Error: Qwen model archive not found." >&2
    exit 1
}

mkdir -p "$OFFLINE_DIR/image" "$OFFLINE_DIR/models"

cp -f "$IMAGE_ARCHIVE" \
    "$OFFLINE_DIR/image/ravi-ollama-image.tar"

cp -f "$MODEL_ARCHIVE" \
    "$OFFLINE_DIR/models/qwen2.5-0.5b.tar"

echo "Offline Ollama bundle installed successfully."
