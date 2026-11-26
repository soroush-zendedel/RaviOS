# RaviOS — Open WebUI Integration

**Development Branch:** `develop/open-webui`  
**Base Branch:** `develop/desktop-ollama`  
**Component:** `ravios-webui`  
**Status:** Planning and Implementation Specification

## 1. Objective

The objective of this development phase is to integrate [Open WebUI](https://github.com/open-webui/open-webui) into RaviOS as an independent Docker-based component.

Open WebUI will provide a graphical web interface for interacting with locally hosted AI models through the existing Ollama installation.

Instead of developing a custom AI chat interface and Agent Runtime at this stage, RaviOS will initially use the existing capabilities provided by Open WebUI.

The implementation must remain independent of the current operating system build and must not disrupt existing functionality.

## 2. Git Branch Strategy

All implementation work must take place in a new branch:

- Base: `develop/desktop-ollama`
- New branch: `develop/open-webui`

The existing `develop/desktop-ollama` branch must remain unchanged during this development phase.

All changes related to Open WebUI integration must be committed to `develop/open-webui`.

## 3. Independent Docker Image

Open WebUI must be packaged as an independent Docker image.

The image must be built and tested in the RaviOS development environment before being integrated into the operating system.

The component and Docker image identity will be:

`ravios-webui`

The final exported image must be placed at:

```text
artifacts/
└── ravios-webui/
    ├── image/
    │   └── ravios-webui-image.tar
    └── README
```

The README must document:

- Open WebUI version and source.
- Image build process.
- Runtime configuration.
- Networking requirements.
- Persistent storage requirements.
- Testing procedures.
- RaviOS integration instructions.

The image must be reproducible from the project source and build configuration.

## 4. Development and Testing

Open WebUI must first be built and tested independently in the development environment.

The existing RaviOS build outputs and running components must not be modified or rebuilt during this phase.

The following functionality must be evaluated.

### 4.1 Ollama Integration

- Connect Open WebUI to the existing `ravi-ollama` container.
- Use the existing Ollama API and locally available models.
- Verify model discovery and chat functionality.
- Do not replace, rebuild, or modify the existing Ollama image or container configuration.

### 4.2 Open WebUI Features

Evaluate and test the capabilities available in the selected Open WebUI version, including:

- Web-based AI chat.
- Conversation and session management.
- File uploads and document processing.
- RAG and Knowledge Base functionality.
- MCP integration.
- Tool calling and supported integrations.
- OpenAI-compatible and other available API capabilities.
- User and model configuration.

The objective is to use existing Open WebUI functionality wherever possible rather than reimplementing it.

### 4.3 Chromium Integration

Open WebUI must be accessible through the existing Chromium browser in RaviOS.

The existing Chromium image and its current functionality must remain unchanged.

Any required Docker networking changes must be handled without modifying or rebuilding the Chromium image.

### 4.4 Resource and Stability Testing

Evaluate:

- RAM consumption.
- CPU consumption.
- Startup time.
- Response time.
- Container stability.
- Persistence of conversations, settings, and uploaded data.
- Recovery after container restart.

The selected Open WebUI version and Docker image configuration must be documented.

## 5. Networking

Open WebUI must use its default application port:

`8080`

The container must listen on its normal container network interface.

The intended Docker networking configuration is:

- Container name: `ravios-webui`
- Internal application port: `8080`
- Host-side published port: `127.0.0.1:8080`
- Host-side port mapping: `127.0.0.1:8080:8080`

The direct host endpoint is:

```text
http://127.0.0.1:8080
```

For container-to-container communication, the intended Open WebUI endpoint is:

```text
http://ravios-webui:8080
```

This address is intended for internal Docker network access, including access from the existing Chromium container.

The existing Ollama container must be reachable from Open WebUI through Docker networking.

If a shared Docker network is required, it must be introduced without rebuilding or modifying the existing Ollama and Chromium images.

The existing Chromium container must be able to access Open WebUI through the selected Docker networking configuration.

Port `999` is not part of this integration phase. It may be considered later for a dedicated RaviOS Agent API if required.

No additional local DNS, hostname alias, or browser address-shortcut configuration is required in this phase.

## 6. Persistent Storage

All persistent Open WebUI data must be stored using Docker volumes backed by the existing Docker Data partition.

The implementation must not introduce a separate host-level persistence mechanism.

Persistent data should include, as supported by the selected Open WebUI version:

- Application configuration.
- User settings.
- Conversations and chat history.
- Uploaded documents.
- Knowledge Base data.
- Application metadata.

The existing Docker Data partition is used by Docker Engine at:

```text
/var/lib/docker
```

The integration must reuse this infrastructure.

The Open WebUI persistent data volume must be mounted at:

```text
/app/backend/data
```

A persistent `WEBUI_SECRET_KEY` must also be configured so that container recreation does not invalidate existing sessions.

## 7. Operating System Integration

After successful development and testing, the exported Docker image will be integrated into the RaviOS offline image-loading mechanism.

The intended offline image location inside the operating system is:

```text
/usr/share/ravios/offline/ravios-webui/image/ravios-webui-image.tar
```

The first operating system startup must:

1. Check whether the `ravios-webui` image is already available.
2. Load the image from the offline archive if necessary.
3. Create the required persistent Docker volume.
4. Create and configure the `ravios-webui` container if it does not already exist.
5. Configure automatic container startup using Docker's restart policy.
6. Publish the service on `127.0.0.1:8080`.
7. Start the WebUI service.

Subsequent operating system startups must reuse the existing image, container, and persistent volume.

They must not rebuild or reload the image unnecessarily.

The startup behavior should follow the existing architecture used by the Chromium and Ollama Docker components.

The image-loading and container-startup implementation must be completed only after the independent image has passed development and integration testing.

## 8. Existing System Preservation

The following existing components must remain unchanged during independent development and testing:

- Current RaviOS Buildroot build outputs.
- Current operating system image.
- Existing RootFS configuration.
- Existing `ravi-ollama` image and container.
- Existing Chromium image and container configuration.
- Existing Docker Data partition implementation.

No unnecessary package installation, removal, or RootFS modification is permitted during the independent development phase.

Any operating system integration changes required for automatic first-start image loading must be deferred until the image is approved.

## 9. Future Architecture

This phase intentionally does not implement a custom RaviOS Agent Runtime.

Open WebUI will initially provide the available chat, RAG, MCP, and tool integration capabilities.

A future development phase may introduce an independent component named:

`ravios-agent`

Its responsibilities may include:

- A custom Agent Runtime.
- Dynamic MCP Server discovery and lifecycle management.
- A dedicated CLI named `ravi`.
- RaviOS-specific system integration.
- Additional automation and tool orchestration.
- Shared backend functionality for multiple interfaces.

The future Agent implementation must be designed to coexist with Open WebUI and reuse existing services where appropriate.

The current phase must not introduce artificial limits on the number of MCP Servers or tools available to the system.

The choice of Ollama model and its actual capabilities remain user-controlled.

## 10. Acceptance Criteria

This phase is considered complete when:

1. The `develop/open-webui` branch exists and is based on `develop/desktop-ollama`.
2. An independent `ravios-webui` Docker image can be built reproducibly.
3. The exported image exists at the specified artifacts path.
4. Open WebUI successfully connects to the existing Ollama service.
5. Local model discovery and chat functionality work.
6. The selected RAG, MCP, and tool capabilities have been tested and documented.
7. Open WebUI is accessible through the existing Chromium browser.
8. The host-side direct endpoint is `http://127.0.0.1:8080`.
9. Internal Docker communication uses `http://ravios-webui:8080`.
10. Persistent data survives container restarts.
11. Resource consumption and runtime behavior have been evaluated.
12. The final image can be loaded offline and its container created automatically on the first RaviOS startup.
13. Subsequent boots reuse the existing container without rebuilding or reloading the image.
14. Existing RaviOS functionality remains intact.

**The primary deliverable of this phase is a tested, independently packaged `ravios-webui` Docker image ready for offline integration into RaviOS.**
