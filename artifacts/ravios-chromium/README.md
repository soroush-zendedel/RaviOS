# ravios-chromium.tar

Place ravios-chromium.tar here before building the system image.

On Windows (from project root), after building the image:

  docker save ravios-chromium:latest -o buildroot-external\rootfs-overlay\usr\share\ravios\docker-images\ravios-chromium.tar

Or run:  .\docker\chromium\prepare-image.ps1

The session hook will docker load this file on first start if the image is missing.
