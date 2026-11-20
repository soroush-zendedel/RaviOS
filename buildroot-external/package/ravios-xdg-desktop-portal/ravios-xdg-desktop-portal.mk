RAVIOS_XDG_DESKTOP_PORTAL_VERSION = 1.21.1
RAVIOS_XDG_DESKTOP_PORTAL_SOURCE = xdg-desktop-portal-1.21.1.tar.xz
RAVIOS_XDG_DESKTOP_PORTAL_SITE = https://github.com/flatpak/xdg-desktop-portal/releases/download/1.21.1
RAVIOS_XDG_DESKTOP_PORTAL_LICENSE = GPL-2.0-or-later
RAVIOS_XDG_DESKTOP_PORTAL_LICENSE_FILES = COPYING
RAVIOS_XDG_DESKTOP_PORTAL_DEPENDENCIES = host-pkgconf libglib2 json-glib libfuse3 gdk-pixbuf gstreamer1 gst1-plugins-base pipewire
RAVIOS_XDG_DESKTOP_PORTAL_CONF_OPTS = -Dflatpak-interfaces=disabled -Dsystemd=disabled -Dgeoclue=disabled -Dgudev=disabled -Dtests=disabled -Ddocumentation=disabled -Dman-pages=disabled -Dinstalled-tests=false -Dsandboxed-image-validation=disabled -Dsandboxed-sound-validation=disabled -Ddbus-service-dir=/usr/share/dbus-1/services
RAVIOS_XDG_DESKTOP_PORTAL_INSTALL_STAGING = YES
$(eval $(meson-package))
