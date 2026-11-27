#!/bin/sh

set -eu

BOARD_DIR="$(dirname "$0")"
PROJECT_ROOT="$(CDPATH= cd -- "$BOARD_DIR/../../../.." && pwd)"
DOCKER_DATA_MODE="${RAVIOS_DOCKER_DATA:-Create}"

EFI_SIZE_MIB=256
GPT_START_RESERVE_MIB=1
GPT_END_RESERVE_MIB=1
MIB=1048576

echo "===== Checking UEFI build artifacts ====="

test -f "$BINARIES_DIR/bzImage"
test -f "$BINARIES_DIR/rootfs.ext2"
test -f "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi"

ROOTFS_SIZE_BYTES="$(wc -c < "$BINARIES_DIR/rootfs.ext2")"
ROOTFS_SIZE_MIB=$(((ROOTFS_SIZE_BYTES + MIB - 1) / MIB))

echo "===== Selecting disk layout ====="

case "$DOCKER_DATA_MODE" in
    Create)
        DISK_SIZE="${RAVIOS_DISK_SIZE:-16G}"

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

        DOCKER_DATA_SIZE_MIB=$((DISK_SIZE_MIB - GPT_START_RESERVE_MIB - EFI_SIZE_MIB - ROOTFS_SIZE_MIB - GPT_END_RESERVE_MIB))

        if [ "$DOCKER_DATA_SIZE_MIB" -le 0 ]; then
            echo "Error: Not enough disk space for Docker Data." >&2
            exit 1
        fi

        DOCKER_DATA_SIZE="${DOCKER_DATA_SIZE_MIB}M"
        GENIMAGE_CONFIG="$BOARD_DIR/genimage-uefi.cfg"

        echo "Docker Data:     $DOCKER_DATA_SIZE"
        echo "Disk Size:       $DISK_SIZE"
        ;;

    None)
        GENIMAGE_CONFIG="$BOARD_DIR/genimage-uefi-no-docker-data.cfg"

        echo "Docker Data:     Disabled"
        echo "Disk Size:       Automatic"
        ;;

    *)
        echo "Error: Invalid Docker Data mode: $DOCKER_DATA_MODE" >&2
        exit 1
        ;;
esac

echo "EFI:             ${EFI_SIZE_MIB}M"
echo "RootFS:          ${ROOTFS_SIZE_MIB}M"

if [ "$DOCKER_DATA_MODE" = "Create" ]; then
    echo "GPT start space: ${GPT_START_RESERVE_MIB}M"
    echo "GPT end space:   ${GPT_END_RESERVE_MIB}M"
fi

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

# ----------------------------------------------------------------------
# Prepare Docker Data seed tree on the normal filesystem (no loop mount).
# mke2fs -d will copy this tree into docker-data.ext4 during genimage.
# Layout on the partition root:
#   /ravios-apps/<app>/app.json
#   /ravios-apps/<app>/image.tar
# ----------------------------------------------------------------------
prepare_docker_data_seed() {
    # IMPORTANT: only the seed path is written to stdout (captured by caller).
    # All status messages go to stderr.
    SEED_ROOT="$BINARIES_DIR/docker-data-root"
    rm -rf "$SEED_ROOT"
    mkdir -p "$SEED_ROOT"

    if [ "$DOCKER_DATA_MODE" != "Create" ]; then
        echo "===== Skipping app seed tree (Docker Data mode is not Create) =====" >&2
        printf '%s\n' "$SEED_ROOT"
        return 0
    fi

    APPS_SRC="$PROJECT_ROOT/artifacts/ravios-apps"
    SEED_APPS="$SEED_ROOT/ravios-apps"
    mkdir -p "$SEED_APPS"

    echo "===== Preparing Docker Data seed tree (no loop-mount) =====" >&2
    echo "Source: $APPS_SRC" >&2
    echo "Seed:   $SEED_APPS" >&2

    if [ ! -d "$APPS_SRC" ]; then
        echo "WARNING: $APPS_SRC not found; Docker Data will be empty of apps." >&2
        printf '%s\n' "$SEED_ROOT"
        return 0
    fi

    for app_dir in "$APPS_SRC"/*; do
        [ -d "$app_dir" ] || continue
        base="$(basename "$app_dir")"
        [ -f "$app_dir/app.json" ] || {
            echo "  skip $base (no app.json)" >&2
            continue
        }

        dest="$SEED_APPS/$base"
        mkdir -p "$dest"
        cp -a "$app_dir/." "$dest/"

        # Normalize alternate tar names to image.tar
        if [ ! -s "$dest/image.tar" ]; then
            for alt in "$dest"/*.tar; do
                [ -f "$alt" ] || continue
                case "$(basename "$alt")" in
                    image.tar) ;;
                    *)
                        echo "  normalizing $(basename "$alt") -> image.tar for $base" >&2
                        mv -f "$alt" "$dest/image.tar"
                        break
                        ;;
                esac
            done
        fi

        # Drop prepare stamp from the seeded image (build-host only)
        rm -f "$dest/.prepare-stamp"

        if [ -s "$dest/image.tar" ]; then
            echo "  prepared $base (image.tar present)" >&2
        else
            echo "  prepared $base metadata only (WARNING: no image.tar)" >&2
        fi
    done

    printf '%s\n' "$SEED_ROOT"
}

echo "===== Preparing Genimage configuration ====="

if [ "$DOCKER_DATA_MODE" = "Create" ]; then
    SEED_ROOT="$(prepare_docker_data_seed)"
    # mke2fs -d needs an absolute path; SEED_ROOT must be a single path line
    SEED_ROOT_ABS="$(CDPATH= cd -- "$SEED_ROOT" && pwd)"

    sed \
        -e "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
        -e "s/DISK_SIZE_PLACEHOLDER/$DISK_SIZE/g" \
        -e "s/DOCKER_DATA_SIZE_PLACEHOLDER/$DOCKER_DATA_SIZE/g" \
        -e "s|DOCKER_DATA_SEED_PLACEHOLDER|$SEED_ROOT_ABS|g" \
        "$GENIMAGE_CONFIG" \
        > "$BINARIES_DIR/genimage-uefi.cfg"

    echo "Docker Data seed directory for mke2fs -d: $SEED_ROOT_ABS"
else
    sed \
        -e "s/ROOT_PARTUUID/$ROOT_PARTUUID/g" \
        "$GENIMAGE_CONFIG" \
        > "$BINARIES_DIR/genimage-uefi.cfg"
fi

echo "===== Creating RaviOS UEFI disk image ====="

support/scripts/genimage.sh \
    -c "$BINARIES_DIR/genimage-uefi.cfg"

echo "===== RaviOS UEFI image generation completed ====="

# Optional cleanup of the temporary seed tree (the data is already inside docker-data.ext4)
if [ -d "$BINARIES_DIR/docker-data-root" ]; then
    rm -rf "$BINARIES_DIR/docker-data-root"
fi

# Punch zero holes so disk.img stays sparse on the build filesystem.
if command -v fallocate >/dev/null 2>&1; then
    echo "===== Sparse-optimizing disk.img (fallocate -d) ====="
    fallocate -d "$BINARIES_DIR/disk.img" || true
elif command -v truncate >/dev/null 2>&1; then
    if cp --sparse=always "$BINARIES_DIR/disk.img" "$BINARIES_DIR/disk.img.sparse" 2>/dev/null; then
        mv -f "$BINARIES_DIR/disk.img.sparse" "$BINARIES_DIR/disk.img"
    fi
fi

IMAGE_SIZE_BYTES="$(wc -c < "$BINARIES_DIR/disk.img")"
IMAGE_BLOCKS_APPARENT="$(du -B1 "$BINARIES_DIR/disk.img" 2>/dev/null | awk '{print $1}')"
echo "Final image logical size:  $IMAGE_SIZE_BYTES bytes"
if [ -n "$IMAGE_BLOCKS_APPARENT" ]; then
    echo "Final image on-disk size:  $IMAGE_BLOCKS_APPARENT bytes (sparse)"
fi
