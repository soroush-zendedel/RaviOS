# Chromium + Foot co-start

## Boot flow

1. S60 dockerd
2. S70 ravios-chromium-image  -> docker load if needed (first boot only, before desktop)
3. S90 ravios-session -> Niri
4. session.d/05-chromium.sh  -> docker run (fast; image already local)
5. session.d/10-foot.sh      -> foot

First boot: longer at boot (load tar), desktop should show Foot and Chromium close together.
Later boots: no load; only container start.

## Build

```powershell
.\build.ps1 -Target VMware -DockerData Create -DiskSize 8G
```

prepare-image runs automatically from build.ps1 and writes `artifacts/ravios-chromium/image/ravios-chromium.tar`.
The Buildroot `post-build.sh` hook copies that artifact into `/usr/share/ravios/docker-images/` in the target rootfs. Verify the tar exists in both locations after a successful build.
