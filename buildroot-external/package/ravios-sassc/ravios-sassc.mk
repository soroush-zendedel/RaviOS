################################################################################
#
# ravios-sassc (host)
#
################################################################################

HOST_RAVIOS_SASSC_VERSION = a1950c2d95ea4c051feb90bb1f43559fbb54bf36
HOST_RAVIOS_SASSC_SOURCE = sassc-$(HOST_RAVIOS_SASSC_VERSION).tar.gz
HOST_RAVIOS_SASSC_SITE = https://github.com/lazka/sassc/archive
HOST_RAVIOS_SASSC_LICENSE = MIT
HOST_RAVIOS_SASSC_LICENSE_FILES = LICENSE
HOST_RAVIOS_SASSC_DEPENDENCIES = host-ravios-libsass host-pkgconf

$(eval $(host-meson-package))
