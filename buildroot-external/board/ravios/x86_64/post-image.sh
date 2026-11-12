#!/bin/sh

set -eu

BOARD_DIR="$(dirname "$0")"
DISK_SIZE="${RAVIOS_DISK_SIZE:-16G}"

EFI_SIZE_MIB=256
GPT_START_RESERVE_MIB=1
GPT_END_RESERVE_MIB=1
MIB=1048576

echo "===== Checking UEFI build artifacts ====="

test -f "$BINARIES_DIR/bzImage"
test -f "$BINARIES_DIR/rootfs.ext2"
test -f "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi"

echo "===== Calculating disk layout ====="

case "$DISK_SIZE" in
    *G)
        DISK_SIZE_GB="${DISK_SIZE%G}"
        ;;
    *)
        echo "Error: Invalid disk size: $DISK_SIZE" >&2
        exit 1
        ;;
esac

case "$DISK_SIZE_GB" in
    ''|*[!0-9]*)
        echo "Error: Invalid disk size: $DISK_SIZE" >&2
        exit 1
        ;;
esac

if [ "$DISK_SIZE_GB" -lt 3 ]; then
    echo "Error: Disk size must be at least 3G." >&2
    exit 1
fi

DISK_SIZE_MIB=$((DISK_SIZE_GB * 1024))

ROOTFS_SIZE_BYTES="$(wc -c < "$BINARIES_DIR/rootfs.ext2")"
ROOTFS_SIZE_MIB=$(((ROOTFS_SIZE_BYTES + MIB - 1) / MIB))

DOCKER_DATA_SIZE_MIB=$((DISK_SIZE_MIB - GPT_START_RESERVE_MIB - EFI_SIZE_MIB - ROOTFS_SIZE_MIB - GPT_END_RESERVE_MIB))

if [ "$DOCKER_DATA_SIZE_MIB" -le 0 ]; then
    echo "Error: Not enough disk space for Docker Data." >&2
    exit 1
fi

DOCKER_DATA_SIZE="${DOCKER_DATA_SIZE_MIB}M"

echo "Disk Size:       $DISK_SIZE"
echo "EFI:             ${EFI_SIZE_MIB}M"
echo "RootFS:          ${ROOTFS_SIZE_MIB}M"
echo "Docker Data:     $DOCKER_DATA_SIZE"
echo "GPT start space: ${GPT_START_RESERVE_MIB}M"
echo "GPT end space:   ${GPT_END_RESERVE_MIB}M"

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

echo "===== Preparing GRUB configuration ====="

sed "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
    "$BOARD_DIR/grub-uefi.cfg" \
    > "$BINARIES_DIR/efi-part/EFI/BOOT/grub.cfg"

echo "===== Preparing Genimage configuration ====="

sed \
    -e "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
    -e "s/DISK_SIZE_PLACEHOLDER/$DISK_SIZE/g" \
    -e "s/DOCKER_DATA_SIZE_PLACEHOLDER/$DOCKER_DATA_SIZE/g" \
    "$BOARD_DIR/genimage-uefi.cfg" \
    > "$BINARIES_DIR/genimage-uefi.cfg"

echo "===== Creating RaviOS UEFI disk image ====="

support/scripts/genimage.sh \
    -c "$BINARIES_DIR/genimage-uefi.cfg"

echo "===== RaviOS UEFI image generation completed ====="