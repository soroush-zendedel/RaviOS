#!/bin/sh
# Chromium is intentionally NOT started with the desktop session.
# Manifest: artifacts/ravios-apps/chromium/app.json -> "autostart": false
#
# Start manually from foot:
#   chromium
#   chromium --temp
#   chromium --logs
#   ravios-app start chromium
#
# Implementation: generic Application Manager (/usr/bin/ravios-app).
# No per-app launch script.

exit 0
