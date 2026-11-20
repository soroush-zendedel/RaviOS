RAVIOS_XDG_DESKTOP_PORTAL_GNOME_VERSION = 51.0
RAVIOS_XDG_DESKTOP_PORTAL_GNOME_SOURCE = xdg-desktop-portal-gnome-51.0.tar.xz
RAVIOS_XDG_DESKTOP_PORTAL_GNOME_SITE = https://download.gnome.org/sources/xdg-desktop-portal-gnome/51
RAVIOS_XDG_DESKTOP_PORTAL_GNOME_LICENSE = LGPL-2.1+
RAVIOS_XDG_DESKTOP_PORTAL_GNOME_LICENSE_FILES = COPYING

RAVIOS_XDG_DESKTOP_PORTAL_GNOME_DEPENDENCIES = \
host-pkgconf \
ravios-xdg-desktop-portal \
libglib2 \
libgtk4 \
ravios-libadwaita \
ravios-gnome-desktop \
fontconfig \
gsettings-desktop-schemas

RAVIOS_XDG_DESKTOP_PORTAL_GNOME_CONF_OPTS = \
-Dsystemd=disabled \
-Dsystemduserunitdir=/usr/lib/systemd/user \
-Ddbus_service_dir=/usr/share/dbus-1/services

RAVIOS_XDG_DESKTOP_PORTAL_GNOME_CONF_ENV = PKG_CONFIG_SYSROOT_DIR=/workspace/output/staging

$(eval $(meson-package))
