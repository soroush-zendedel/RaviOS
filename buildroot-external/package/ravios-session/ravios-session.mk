RAVIOS_SESSION_DEPENDENCIES = niri dbus pipewire wireplumber seatd

define RAVIOS_SESSION_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(BR2_EXTERNAL_RAVIOS_PATH)/package/ravios-session/ravios-session \
        $(TARGET_DIR)/usr/bin/ravios-session
endef

$(eval $(generic-package))
