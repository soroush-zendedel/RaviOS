# Application Manager Implementation Notes

This document records the implementation of the generic, manifest-driven Application Manager described in `application-manifast.md`.

## Design goal achieved

**There are no per-application shell launch scripts.**

Any Docker image that ships a valid `app.json` under `/var/lib/docker/ravios-apps/<name>/` is:

1. Discoverable by `ravios-app list`
2. Startable by `ravios-app start <name>`
3. Directly available on the PATH as its `cli_name` (e.g. typing `chromium` or `webui`)

The single binary `/usr/bin/ravios-app` handles everything. When invoked via a symlink whose basename matches a known `cli_name`, it automatically runs `start <cli_name>`.

## Core components

| Path | Role |
|------|------|
| `/usr/bin/ravios-app` | CLI + runtime entry point |
| `/usr/libexec/ravios/app-runtime.sh` | Shared library (JSON, discovery, providers, pre-start, CLI links) |
| `/usr/libexec/ravios/providers/*.sh` | Modular resource providers |
| `/etc/init.d/S71ravios-app-cli` | Boot-time creation of `/usr/bin/<cli_name>` symlinks |

### Resource providers

| Provider | File | Responsibility |
|----------|------|----------------|
| Display  | display.sh | Wayland socket, XDG_RUNTIME_DIR, ravios-display-group |
| GPU      | gpu.sh | /dev/dri, ravios-gpu-group → host `video` group |
| Audio    | audio.sh | PipeWire socket, ravios-audio-group |
| Network  | network.sh | Named shared networks with reference tracking |
| Volume   | volume.sh | Docker volumes (persistent by default) |

Providers emit a simple line-oriented protocol (`ENV:`, `VOLUME:`, `DEVICE:`, `GROUP:`, `NETWORK:`, `FLAG:`) that the core runtime turns into `docker run` arguments.

## Manifest extensions used by the generic path

```json
{
  "cli_name": "chromium",
  "command": [ "chromium", "--ozone-platform=wayland", "..." ],
  "rm": true,
  "pre_start": {
    "clear_locks": {
      "volume": "ravios-chromium-data",
      "paths": [ "SingletonLock", "..." ]
    }
  },
  "resources": {
    "display": true,
    "gpu": true,
    "audio": true,
    "networks": [ { "name": "ravios-net", "mode": "shared" } ],
    "volumes": [
      { "name": "ravios-chromium-data", "target": "/data", "persistent": true },
      { "name": "ravios-chromium-cache", "target": "/cache", "persistent": true }
    ]
  }
}
```

- **`command`** – replaces every former hard-coded launch script argument list.
- **`rm`** – if true, the container is started with `--rm` (suitable for GUI one-shots).
- **`pre_start.clear_locks`** – generic, declarative cleanup of stale lock files on a named volume before start. No Chromium-specific code remains in the runtime.

Legacy fields (`ports`, `environment`, `env_from_host`, `depends_on`, top-level `volumes`/`networks`) continue to work.


## Environment variables

The runtime supports three complementary sources of environment variables. All of them are turned into `docker run -e KEY=VALUE` arguments.

### 1. Static values in the manifest

```json
"environment": {
  "OLLAMA_HOST": "0.0.0.0:11434",
  "OLLAMA_MODELS": "/models",
  "WEBUI_AUTH": "false",
  "LANG": "C.UTF-8"
}
```

String, boolean and numeric values are accepted.

### 2. Selected host variables (`env_from_host`)

```json
"env_from_host": [ "LANG", "LC_ALL", "TZ", "WAYLAND_DISPLAY" ]
```

Only variables that are actually set in the host environment are passed; empty values are skipped so the container is not given blank overrides.

### 3. Provider-emitted variables

Resource providers may emit `ENV:KEY=VALUE` lines (for example the display provider sets `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`). These are applied automatically.

### 4. Built-in helpers

If the manifest contains `"secret_key": true` (usually under `extra`), the runtime generates or reuses a secret and injects `WEBUI_SECRET_KEY`.

Order of application: provider env → static `environment` → `env_from_host` → helpers. Later sources override earlier ones for the same key when Docker processes the final argument list.

## Security baseline (applied to every container)

- `--security-opt=no-new-privileges:true`

The runtime never adds:

- `CAP_SYS_ADMIN` / `CAP_SYS_PTRACE`
- `seccomp=unconfined` / `apparmor=unconfined`
- `--no-sandbox`
- `--ipc=host` (unless a future verified requirement appears)

Chromium now travels the same path and relies on the host’s custom Docker seccomp profile + User Namespace support that were already verified.

## How a user starts an application

```sh
# After first boot (or after "ravios-app install-cli"):
chromium          # symlink → ravios-app → start chromium
webui
ollama

# Or explicitly:
ravios-app start chromium
ravios-app list
ravios-app status webui
ravios-app stop ollama
```

## Lifecycle

1. Discover app via folder name or `name` / `cli_name`.
2. Start any `depends_on` apps first (depth-limited recursion).
3. Load the Docker image from the seed tar if necessary.
4. Run declarative `pre_start` actions (e.g. clear_locks).
5. Call each requested resource provider.
6. Assemble and execute `docker run` with resolved resources + security baseline + `command` from the manifest.
7. On stop: stop the container and drop this app’s network references.
8. On remove: remove only the container; volumes and shared networks stay.

Shared networks are reference-counted so that stopping one consumer never destroys a network still used by others.

## Files

```
buildroot-external/rootfs-overlay/usr/bin/ravios-app
buildroot-external/rootfs-overlay/usr/libexec/ravios/app-runtime.sh
buildroot-external/rootfs-overlay/usr/libexec/ravios/providers/{display,gpu,audio,network,volume}.sh
buildroot-external/rootfs-overlay/etc/init.d/S71ravios-app-cli
artifacts/ravios-apps/chromium/app.json   (now fully generic, no load_only)
artifacts/ravios-apps/ollama/app.json
artifacts/ravios-apps/webui/app.json
docs/development/application-manager-implementation.md
```

The old `chromium-launch.sh` has been removed. A `.orig` copy is retained only as historical reference and is not installed.


## Importing arbitrary Docker images

Any local (or pullable) Docker image can be registered without a hand-written manifest:

```sh
ravios-app import python:3.14
ravios-app import python:3.14 --name python314
ravios-app import --scan          # list images with no manifest
ravios-app import --scan --yes    # import all of them
```

A template `app.json` is written under `/var/lib/docker/ravios-apps/<cli_name>/` and a CLI symlink is created. The user can then edit the manifest to enable volumes, environment, display/gpu/audio, custom `command`, etc.

### Default shared network

Every imported container is placed on the shared network **`ravios-net`** (override with env `RAVIOS_DEFAULT_NETWORK`). Built-in apps (chromium, ollama, webui) already use the same network. Changing policies, isolation, or connectivity on this network therefore applies to the whole application set as a single management layer.




## Live default template (no per-image file)

Images that do **not** have a materialised manifest under
`/var/lib/docker/ravios-apps/<cli>/app.json` use
**`/etc/ravios/app-template.json` at runtime**.

- Changing the system template immediately affects every such image.
- Typing the sanitized image name (e.g. `python-3-14`) resolves the live
  template, creates no permanent app.json, and starts the container.
- `ravios-app import <image>` **materialises** a private copy under
  `SEED_ROOT` so that image can be customised independently. After import,
  further template edits no longer affect that app.

| State | Manifest source |
|-------|-----------------|
| Not imported | Live `/etc/ravios/app-template.json` |
| Imported / hand-written | `/var/lib/docker/ravios-apps/<cli>/app.json` |

## System-wide default manifest template

Path: **`/etc/ravios/app-template.json`**

Every `ravios-app import` and every on-demand auto-import (typing a cli_name that matches a local image) generates the app manifest by substituting placeholders in this file:

| Placeholder | Replaced with |
|-------------|-----------------|
| `{{cli_name}}` | Sanitized CLI / directory name |
| `{{image}}` | Full image reference (e.g. `python:3.14`) |
| `{{default_network}}` | Value of `RAVIOS_DEFAULT_NETWORK` (default `ravios-net`) |
| `{{volume_name}}` | `ravios-data-<cli_name>` |

Edit this file on the running system to change defaults for all **future** imports. Existing app manifests under `/var/lib/docker/ravios-apps/` are not rewritten automatically.

Override path with env `RAVIOS_APP_TEMPLATE` if needed. If the file is missing, a minimal built-in fallback is used.

## Runtime flags and defaults

| Flag / default | Behaviour |
|----------------|-----------|
| `--temp` | Skip all persistent volume mounts for this run only |
| `--logs` | Print the last 33 lines of the container log and exit |
| Default network | `ravios-net` (shared; every managed app joins it) |
| Default volume | `ravios-data-<cli_name>` mounted at `/data` |
| Global env | Host `TZ` and `LANG` injected unless the manifest already sets them |
| Limits | Optional manifest fields: `memory`, `cpus`, `cap_add`, `cap_drop` |

Examples:

```sh
chromium --temp          # no persistent profile
chromium --logs          # last 33 log lines
ravios-app import nginx:alpine --update
python-3-14              # auto-import if image exists and no manifest yet
```

## Remaining optional work

- Stronger JSON parsing if a lightweight parser becomes available on the host.
- Future security policy engine (authorization layer between declaration and resolution).
- AppArmor once kernel support lands.
- Automatic generation of `.desktop` files for GUI apps from the same manifests.
