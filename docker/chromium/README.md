# RaviOS Chromium (Docker)

Minimal Chromium as a Wayland client. Auto-starts with the desktop session.

## Offline image artifact

The Chromium image is kept outside the Buildroot rootfs overlay, alongside the other generated RaviOS artifacts.

Run from the project root:

```powershell
.\docker\chromium\prepare-image.ps1
```

This builds (when needed) and saves the image to:

`artifacts/ravios-chromium/image/ravios-chromium.tar`

During the Buildroot post-build stage, `buildroot-external/board/ravios/x86_64/post-build.sh` copies that tar into the target root filesystem at:

`/usr/share/ravios/docker-images/ravios-chromium.tar`

The build fails with a clear error if the artifact is missing or empty, rather than silently producing an image without offline Chromium.

Then build the system:

```powershell
.\build.ps1 -Target VMware -DockerData Create -DiskSize 8G
```

At boot, `S70ravios-chromium-image` loads the image into Docker before the desktop session starts. The `05-chromium.sh` session hook retains a fallback load if the image is not already present.

## Manual build

```sh
docker/chromium/build.sh
```

This builds the Docker image and saves the tar to the same `artifacts/ravios-chromium/image/` location.

## Runtime behaviour

- Foot: native host binary (session hook `10-foot.sh`)
- Chromium: Docker container `ravios-chromium:latest` (session hook `05-chromium.sh`)
- GPU: best-effort; full acceleration expected on real Intel/AMD hardware
