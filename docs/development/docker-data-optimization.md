# RaviOS – Docker Data / App Loading Optimization

**Date:** 2026-11-26  
**Goal:** Keep rootfs free of Docker image tarballs. Seed apps directly onto the Docker Data volume. Replace hardcoded per-app init scripts with a generic Application Manager.

## Summary of changes

### 1. Rootfs no longer contains image tarballs
- `post-build.sh` no longer copies Chromium / Ollama / WebUI `.tar` files into `/usr/share/ravios/...`.
- Old directories are explicitly removed if present.
- Result: significantly smaller rootfs that only contains OS components.

### 2. Unified app layout under `artifacts/ravios-apps/`
Every offline app lives in one place:

```
artifacts/ravios-apps/
  ├── chromium/
  │     ├── app.json
  │     └── image.tar          ← written by docker/chromium/prepare-image.ps1
  ├── ollama/
  │     ├── app.json
  │     ├── README.md
  │     ├── image.tar          ← place offline Ollama image here
  │     └── models/
  │           └── qwen2.5-0.5b.tar
  └── webui/
        ├── app.json
        ├── image.tar          ← written by docker/webui/prepare-image.ps1
        └── .prepare-stamp
```

- `prepare-image.ps1` scripts for Chromium and WebUI now write **directly** to this tree.
- `post-image.sh` discovers every folder that contains `app.json` and seeds it onto the Docker Data partition (no hardcoded per-app copy paths).

### 3. Seed onto Docker Data at image-build time
When `DOCKER_DATA_MODE=Create`:
- `docker-data.ext4` is loop-mounted.
- Contents of `artifacts/ravios-apps/*` are copied to `/ravios-apps/` on that partition.
- After first successful `docker load` at boot, seed `.tar` files are deleted.

### 4. Generic Application Manager (`S70ravios-apps`)
- Replaces the three hardcoded scripts (`S70ravios-chromium-image`, `S70ollama`, `S71ravios-webui`).
- Discovers every folder under `/var/lib/docker/ravios-apps/` that has a valid `app.json`.
- Ensures declared **networks** (creates if missing) and **volumes**.
- Loads the image when missing or when `version` changed; then removes the seed tar.
- Creates / starts the container according to the declaration.

#### Manifest switches

| Field | Meaning |
|-------|---------|
| `autostart` | `true` (default) = manager creates/starts the container after load. `false` = only ensure the image is loaded. |
| `load_only` | `true` = skip all container management (used by Chromium; the desktop session starts it). |
| `version` | Recorded after load; a different version triggers reload. |
| `load_priority` | Numeric order (lower first). |
| `networks` / `volumes` / `ports` / `environment` | Applied when creating the container. |

### 5. How to add a new app
1. Create `artifacts/ravios-apps/<name>/app.json` (include `autostart`, `version`, etc.).
2. Produce `artifacts/ravios-apps/<name>/image.tar` (via a prepare script or manually).
3. Rebuild with `DOCKER_DATA_MODE=Create`.
4. No rootfs changes required.

### 6. Files touched
- `docker/chromium/prepare-image.ps1` → output to `artifacts/ravios-apps/chromium/image.tar`
- `docker/webui/prepare-image.ps1` → output to `artifacts/ravios-apps/webui/image.tar`
- `buildroot-external/board/ravios/x86_64/post-build.sh`
- `buildroot-external/board/ravios/x86_64/post-image.sh` (convention-based seed)
- `buildroot-external/rootfs-overlay/etc/init.d/S70ravios-apps` (new, with `autostart`)
- Old `S70*` / `S71*` per-app scripts removed
- `buildroot-external/rootfs-overlay/etc/ravios/session.d/05-chromium.sh`
- `artifacts/ravios-apps/{chromium,ollama,webui}/app.json`
- `build.ps1` comment updated

### Notes
- Build host must allow loop-mount of `docker-data.ext4`.
- Legacy folders (`artifacts/ravios-chromium`, `artifacts/ravios-webui`, `artifacts/ollama-bundle`) are no longer used by the build; you can migrate any existing tars into `ravios-apps/` and remove the old folders when ready.
- Ollama still has no automated prepare script; place `image.tar` and model archives under `artifacts/ravios-apps/ollama/` as documented in its README.

---

## Follow-up (2026-11-26): Clean flags, ravios-app CLI, manifest fields

### build.ps1
- `-Clean` now also removes `docker-data.ext4` and related genimage intermediates inside the build container (not only `disk.img`).
- `-CleanRootfs` additionally removes `rootfs.ext2` (and common variants) so the next build regenerates the root filesystem image.
- `-RefreshConfig` forces `make ravios_x86_64_defconfig` so external-tree defconfig changes are applied.

### ravios-app CLI (`/usr/bin/ravios-app`)
```
ravios-app list
ravios-app status [app]
ravios-app start <app>
ravios-app stop <app>
ravios-app restart <app>
ravios-app remove <app>
```
Also accepts the app name alone: `ravios-app webui` → start webui.

### Thin wrappers in PATH
- `chromium` → `ravios-app start chromium`
- `webui` → `ravios-app start webui`
- `ollama` → `ravios-app start ollama`

### Manifest fields
- `cli_name` — alternate name for lookup / wrappers
- `autostart` — manager starts container at boot when true
- `env_from_host` — list of host env var names passed into the container (e.g. Wayland for Chromium)
