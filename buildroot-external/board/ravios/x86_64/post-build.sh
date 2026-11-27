#!/bin/sh

set -e

BOARD_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$BOARD_DIR/../../../.." && pwd)"

# ------------------------------------------------------------
# RaviOS post-build
#
# Application Docker images are NO LONGER embedded into the rootfs.
# They are seeded directly onto the Docker Data partition during
# post-image (see post-image.sh). This keeps the rootfs small and
# free of non-OS payload.
# ------------------------------------------------------------

echo "===== RaviOS post-build: rootfs stays free of Docker image tarballs ====="

# ------------------------------------------------------------
# Set executable permissions for system scripts
# ------------------------------------------------------------

chmod 0755 "$TARGET_DIR/etc/init.d/S05ravios-groups" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/init.d/S50docker-data"
chmod 0755 "$TARGET_DIR/etc/init.d/S60dockerd"
chmod 0755 "$TARGET_DIR/etc/init.d/S70ravios-apps"
chmod 0755 "$TARGET_DIR/usr/sbin/ravios-docker-data"
chmod 0755 "$TARGET_DIR/usr/bin/ravi" 2>/dev/null || true
mkdir -p "$TARGET_DIR/usr/libexec/ravios/providers"
chmod 0755 "$TARGET_DIR/usr/libexec/ravios/app-runtime.sh" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/usr/libexec/ravios/providers/"*.sh 2>/dev/null || true
# CLI aliases: created here (Linux build host), NOT stored as symlinks in the
# Windows-checked-out overlay. Only /usr/bin/ravi lives in rootfs-overlay.
ln -sfn ravi "$TARGET_DIR/usr/bin/ravios-app" 2>/dev/null || true
ln -sfn ravi "$TARGET_DIR/usr/bin/chromium" 2>/dev/null || true
ln -sfn ravi "$TARGET_DIR/usr/bin/webui" 2>/dev/null || true
ln -sfn ravi "$TARGET_DIR/usr/bin/ollama" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/usr/bin/ravios-session" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/ravios/session.d/"*.sh 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/init.d/S90ravios-session" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/init.d/S71ravios-app-cli" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/init.d/S72ravi-image-watch" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/usr/libexec/ravios/docker-image-watch.sh" 2>/dev/null || true
chmod 0755 "$TARGET_DIR/etc/profile.d/10-locale.sh" 2>/dev/null || true
# Drop legacy per-app launcher if a previous rootfs still has it
rm -f "$TARGET_DIR/usr/libexec/ravios/chromium-launch.sh"

# Remove the old per-app init scripts if they still exist in the overlay
rm -f "$TARGET_DIR/etc/init.d/S70ravios-chromium-image"
rm -f "$TARGET_DIR/etc/init.d/S70ollama"
rm -f "$TARGET_DIR/etc/init.d/S71ravios-webui"

# Ensure no leftover image directories are present in the rootfs
rm -rf "$TARGET_DIR/usr/share/ravios/docker-images"
rm -rf "$TARGET_DIR/usr/share/ravios/offline"


# ------------------------------------------------------------
# Ensure RaviOS standard groups exist in the rootfs
# Application Manager providers reference these by name.
# ------------------------------------------------------------
ensure_rootfs_group() {
    _name="$1"
    _gid="$2"
    if [ -f "$TARGET_DIR/etc/group" ] && grep -q "^${_name}:" "$TARGET_DIR/etc/group" 2>/dev/null; then
        return 0
    fi
    echo "${_name}:x:${_gid}:" >> "$TARGET_DIR/etc/group"
}
ensure_rootfs_group video 44
ensure_rootfs_group render 110
ensure_rootfs_group audio 29
ensure_rootfs_group pipewire 122
ensure_rootfs_group input 104

echo "===== post-build completed (lean rootfs) ====="
