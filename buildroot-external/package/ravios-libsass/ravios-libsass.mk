################################################################################
#
# ravios-libsass (host)
#
################################################################################

HOST_RAVIOS_LIBSASS_VERSION = aac79dccd3c8f7e8f22125f87a119f3b1ee9d487
HOST_RAVIOS_LIBSASS_SOURCE = libsass-$(HOST_RAVIOS_LIBSASS_VERSION).tar.gz
HOST_RAVIOS_LIBSASS_SITE = https://github.com/lazka/libsass/archive
HOST_RAVIOS_LIBSASS_LICENSE = MIT
HOST_RAVIOS_LIBSASS_LICENSE_FILES = COPYING LICENSE

$(eval $(host-meson-package))
