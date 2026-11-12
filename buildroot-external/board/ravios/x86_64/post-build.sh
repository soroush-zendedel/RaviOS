#!/bin/sh

set -e

BOARD_DIR="$(dirname "$0")"

cp -f "$BOARD_DIR/grub-bios.cfg" \
    "$TARGET_DIR/boot/grub/grub.cfg"

cp -f "$TARGET_DIR/lib/grub/i386-pc/boot.img" \
    "$BINARIES_DIR/boot.img"

chmod 0755 "$TARGET_DIR/etc/init.d/S50docker-data"
chmod 0755 "$TARGET_DIR/etc/init.d/S60dockerd"