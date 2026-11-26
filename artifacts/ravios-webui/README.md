# ravios-webui

Open WebUI packaged as an independent offline Docker image for RaviOS.

## Source

- Upstream: https://github.com/open-webui/open-webui
- Base image: `openwebui/open-webui:latest` (official Docker Hub; override to ghcr.io if preferred)
- RaviOS image name: `ravios-webui:latest`
- Component identity: `ravios-webui`

## Build process

From the project root on the Windows build host:

```powershell
.\docker\webui\prepare-image.ps1
```

Or let `build.ps1` call it automatically.

The script:

1. Builds (or refreshes) `ravios-webui:latest` from the official Open WebUI image.
2. Exports the archive to:

```text
artifacts/ravios-webui/image/ravios-webui-image.tar
```

`post-build.sh` embeds this archive into the RaviOS rootfs at:

```text
/usr/share/ravios/offline/ravios-webui/image/ravios-webui-image.tar
```

## Runtime configuration

| Setting | Value |
|---------|--------|
| Container name | `ravios-webui` |
| Image | `ravios-webui:latest` |
| Host endpoint | `http://127.0.0.1:8080` |
| Internal endpoint | `http://ravios-webui:8080` |
| Data volume | `ravios-webui-data` → `/app/backend/data` |
| Network | `ravios-net` (shared with `ravi-ollama`) |
| OLLAMA_BASE_URL | `http://ravi-ollama:11434` |
| Auth | Disabled for appliance use (`WEBUI_AUTH=false`) |
| Restart policy | `unless-stopped` |

A persistent `WEBUI_SECRET_KEY` is generated once under `/var/lib/ravios/webui/secret_key` so container recreation does not invalidate sessions.

## Networking

- The init script creates the user-defined network `ravios-net` if missing.
- It connects the existing `ravi-ollama` container to that network without recreating it.
- Open WebUI is started on the same network so it can resolve `ravi-ollama` by name.
- The service is published only on the host loopback interface (`127.0.0.1:8080`).

## Boot behaviour (S71ravios-webui)

1. Wait for Docker Data partition and Docker Engine.
2. Load the offline image if it is not already present.
3. Create the data volume if needed.
4. Ensure a durable secret key exists.
5. Ensure `ravios-net` exists and Ollama is attached.
6. Create the container on first boot, or start it on subsequent boots.
7. Later boots reuse the existing image, volume and container (no reload).

Lexical ordering guarantees `S70ollama` runs before `S71ravios-webui`.

## Testing (independent)

On a machine that already has Docker and a running Ollama:

```powershell
# Build / refresh the image archive
.\docker\webui\prepare-image.ps1 -Force

# Manual smoke test (host)
docker network create ravios-net 2>$null
docker network connect ravios-net ravi-ollama 2>$null
docker volume create ravios-webui-data
docker run -d --name ravios-webui --network ravios-net `
  -p 127.0.0.1:8080:8080 `
  -v ravios-webui-data:/app/backend/data `
  -e WEBUI_SECRET_KEY=dev-test-key `
  -e OLLAMA_BASE_URL=http://ravi-ollama:11434 `
  -e WEBUI_AUTH=false `
  ravios-webui:latest
```

Then open `http://127.0.0.1:8080` in a browser.

## RaviOS integration

After the independent image has been validated:

1. Place the exported tar under `artifacts/ravios-webui/image/`.
2. Rebuild the system image (`build.ps1`); `post-build.sh` embeds the archive.
3. On first boot the `S71ravios-webui` init script performs the load/create steps above.

Existing Chromium, Ollama and Buildroot outputs are not modified by this component.
