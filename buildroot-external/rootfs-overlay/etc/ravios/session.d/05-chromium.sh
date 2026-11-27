#!/bin/sh
# Chromium is intentionally NOT started with the desktop session.
# Manifest: artifacts/ravios-apps/chromium/app.json -> "autostart": false
#
# Start manually from foot:
#   chromium
#   ravios-app start chromium
#
# Launch implementation: /usr/libexec/ravios/chromium-launch.sh

exit 0
