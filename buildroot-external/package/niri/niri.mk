NIRI_VERSION = 8ed0da44d974c32c6877d2f4630c314da0717ecb
NIRI_SITE = https://github.com/YaLTeR/niri.git
NIRI_SITE_METHOD = git
NIRI_LICENSE = GPL-3.0-or-later
NIRI_LICENSE_FILES = LICENSE

NIRI_DEPENDENCIES = \
    host-pkgconf \
    dbus \
    libdrm \
    libinput \
    libxkbcommon \
    mesa3d \
    pango \
    pipewire \
    ravios-libdisplay-info-03 \
    seatd \
    wayland \
    wayland-protocols

NIRI_CARGO_BUILD_OPTS = --no-default-features --features dbus,xdp-gnome-screencast
NIRI_CARGO_INSTALL_OPTS = --no-default-features --features dbus,xdp-gnome-screencast

define NIRI_INSTALL_ASSETS
    $(INSTALL) -D -m 0755 $(@D)/resources/niri-session \
        $(TARGET_DIR)/usr/bin/niri-session
    $(INSTALL) -D -m 0644 $(@D)/resources/niri.desktop \
        $(TARGET_DIR)/usr/share/wayland-sessions/niri.desktop
    $(INSTALL) -D -m 0644 $(@D)/resources/niri-portals.conf \
        $(TARGET_DIR)/usr/share/xdg-desktop-portal/niri-portals.conf
endef

NIRI_POST_INSTALL_TARGET_HOOKS += NIRI_INSTALL_ASSETS

NIRI_KCONFIG_VAR = BR2_PACKAGE_RAVIOS_NIRI
$(eval $(cargo-package))
