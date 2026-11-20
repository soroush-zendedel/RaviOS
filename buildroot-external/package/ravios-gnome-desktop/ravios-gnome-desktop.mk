################################################################################
#
# ravios-gnome-desktop
#
################################################################################

RAVIOS_GNOME_DESKTOP_VERSION = 51.0
RAVIOS_GNOME_DESKTOP_SOURCE = gnome-desktop-51.0.tar.xz
RAVIOS_GNOME_DESKTOP_SITE = https://download.gnome.org/sources/gnome-desktop/51
RAVIOS_GNOME_DESKTOP_LICENSE = GPL-2.0-or-later LGPL-2.1-or-later
RAVIOS_GNOME_DESKTOP_INSTALL_STAGING = YES
RAVIOS_GNOME_DESKTOP_DEPENDENCIES = host-pkgconf libglib2 libgtk4 gdk-pixbuf gsettings-desktop-schemas fontconfig xkeyboard-config eudev libseccomp ravios-iso-codes

RAVIOS_GNOME_DESKTOP_CONF_OPTS = \
    -Dbuild_gtk4=true \
    -Dlegacy_library=false \
    -Dsystemd=disabled \
    -Dudev=enabled \
    -Dintrospection=false \
    -Ddesktop_docs=false \
    -Ddebug_tools=false \
    -Dgtk_doc=false \
    -Dinstalled_tests=false \
    -Dqr=disabled

$(eval $(meson-package))
