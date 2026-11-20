################################################################################
#
# ravios-appstream
#
################################################################################

RAVIOS_APPSTREAM_VERSION = 1.0.5
RAVIOS_APPSTREAM_SOURCE = AppStream-$(RAVIOS_APPSTREAM_VERSION).tar.xz
RAVIOS_APPSTREAM_SITE = https://www.freedesktop.org/software/appstream/releases
RAVIOS_APPSTREAM_LICENSE = LGPL-2.1-or-later
RAVIOS_APPSTREAM_LICENSE_FILES = COPYING
RAVIOS_APPSTREAM_INSTALL_STAGING = YES
RAVIOS_APPSTREAM_DEPENDENCIES = \
host-pkgconf \
libglib2 \
libcurl \
libxml2 \
libyaml \
libxmlb

RAVIOS_APPSTREAM_CONF_OPTS = \
-Dsystemd=false \
-Dgir=false \
-Dvapi=false \
-Dstemming=false \
-Dzstd-support=false \
-Ddocs=false \
-Dapidocs=false \
-Dinstall-docs=false \
-Dcompose=false \
-Dsvg-support=false \
-Dqt=false \
-Dapt-support=false

$(eval $(meson-package))
RAVIOS_APPSTREAM_SUBDIR = AppStream-1.0.5
