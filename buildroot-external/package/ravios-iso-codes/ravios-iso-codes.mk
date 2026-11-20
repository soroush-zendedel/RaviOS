RAVIOS_ISO_CODES_VERSION = v4.20.1
RAVIOS_ISO_CODES_SOURCE = iso-codes-v4.20.1.tar.bz2
RAVIOS_ISO_CODES_SITE = https://salsa.debian.org/iso-codes-team/iso-codes/-/archive/v4.20.1
RAVIOS_ISO_CODES_LICENSE = LGPL-2.1-or-later
RAVIOS_ISO_CODES_LICENSE_FILES = LICENSES/LGPL-2.1-or-later.txt
RAVIOS_ISO_CODES_INSTALL_STAGING = YES

$(eval $(meson-package))
