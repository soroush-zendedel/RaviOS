################################################################################
#
# ravios-libadwaita
#
################################################################################

RAVIOS_LIBADWAITA_VERSION = 1.7.6
RAVIOS_LIBADWAITA_SOURCE = libadwaita-$(RAVIOS_LIBADWAITA_VERSION).tar.xz
RAVIOS_LIBADWAITA_SITE = https://download.gnome.org/sources/libadwaita/1.7
RAVIOS_LIBADWAITA_LICENSE = LGPL-2.1-or-later
RAVIOS_LIBADWAITA_LICENSE_FILES = COPYING
RAVIOS_LIBADWAITA_INSTALL_STAGING = YES
RAVIOS_LIBADWAITA_DEPENDENCIES = host-pkgconf libglib2 libgtk4 libfribidi ravios-appstream host-ravios-sassc

RAVIOS_LIBADWAITA_CONF_OPTS = \
    -Dintrospection=disabled \
    -Dvapi=false \
    -Ddocumentation=false \
    -Dtests=false \
    -Dexamples=false

$(eval $(meson-package))
