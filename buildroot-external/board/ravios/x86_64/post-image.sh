#!/bin/sh

set -eu

BOARD_DIR="$(dirname "$0")"
DISK_SIZE="${RAVIOS_DISK_SIZE:-16G}"

echo "===== Checking UEFI build artifacts ====="

test -f "$BINARIES_DIR/bzImage"
test -f "$BINARIES_DIR/rootfs.ext2"
test -f "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi"

echo "===== Extracting RootFS UUID ====="

ROOT_PARTUUID="$(
    dumpe2fs "$BINARIES_DIR/rootfs.ext2" 2>/dev/null |
    sed -n 's/^Filesystem UUID: *//p'
)"

if [ -z "$ROOT_PARTUUID" ]; then
    echo "Error: Could not determine RootFS UUID." >&2
    exit 1
fi

echo "RootFS PARTUUID: $ROOT_PARTUUID"
echo "Disk Size: $DISK_SIZE"

echo "===== Preparing GRUB configuration ====="

sed "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
    "$BOARD_DIR/grub-uefi.cfg" \
    > "$BINARIES_DIR/efi-part/EFI/BOOT/grub.cfg"

echo "===== Preparing Genimage configuration ====="

sed \
    -e "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
    -e "s/DISK_SIZE_PLACEHOLDER/$DISK_SIZE/g" \
    "$BOARD_DIR/genimage-uefi.cfg" \
    > "$BINARIES_DIR/genimage-uefi.cfg"

echo "===== Creating RaviOS UEFI disk image ====="

support/scripts/genimage.sh \
    -c "$BINARIES_DIR/genimage-uefi.cfg"

echo "===== RaviOS UEFI image generation completed ====="