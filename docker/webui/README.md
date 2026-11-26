# docker/webui — ravios-webui

Thin packaging of the official Open WebUI image for offline use in RaviOS.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | `FROM ghcr.io/open-webui/open-webui:main` + RaviOS labels |
| `prepare-image.ps1` | Build/tag and `docker save` → `artifacts/ravios-webui/image/` |

## Quick prepare

```powershell
.\docker\webui\prepare-image.ps1
# or force a refresh:
.\docker\webui\prepare-image.ps1 -Force
```

See `artifacts/ravios-webui/README.md` for runtime, networking and boot details.
