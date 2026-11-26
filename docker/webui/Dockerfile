# ravios-webui — Open WebUI packaged for offline inclusion in RaviOS.
# Uses the official Open WebUI image as the base so we stay current
# with upstream features (chat, RAG, MCP, tools, etc.).

# Prefer Docker Hub (openwebui/open-webui) — more reachable than ghcr.io in
# restricted networks. Override with --build-arg BASE_IMAGE=... if needed.
ARG BASE_IMAGE=openwebui/open-webui:latest
FROM ${BASE_IMAGE}

# Image identity for RaviOS offline loading and inventory.
LABEL org.opencontainers.image.title="ravios-webui" \
      org.opencontainers.image.description="Open WebUI for RaviOS (Ollama frontend)" \
      org.opencontainers.image.source="https://github.com/open-webui/open-webui" \
      ravios.component="ravios-webui"

# Default listen port inside the container (matches upstream).
EXPOSE 8080

# Persistent application data is mounted at runtime to /app/backend/data.
# WEBUI_SECRET_KEY and OLLAMA_BASE_URL are supplied by the RaviOS init script.
