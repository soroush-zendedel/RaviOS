# RaviOS Application Manifest & Runtime Architecture

## 1. Overview

RaviOS uses a manifest-driven application execution architecture.

Each application declares the resources and capabilities it requires in its own manifest. The RaviOS application runtime reads that manifest, resolves the requested resources, and configures the application environment accordingly.

The manifest is the central source of truth for application requirements.

The runtime is responsible for translating declarative resource requests into concrete host resources, container settings, device access, mounts, environment variables, and network connections.

This architecture must remain generic. It must not be designed specifically around Chromium or any other individual application.

## 2. Core Architectural Principles

The architecture follows these principles:

1. **Manifest-driven:** Applications declare their requirements in their manifests.
2. **Generic runtime:** A single application runtime handles resource allocation and application execution.
3. **Declarative resources:** Manifests describe what an application needs, not how the host implements it.
4. **Resource isolation:** Applications receive only the resources they request.
5. **Shared resources:** Multiple applications can use the same explicitly named shared resources.
6. **Implementation independence:** Manifests must not depend on host-specific paths, numeric GIDs, Docker flags, or other implementation details.
7. **Extensibility:** New resource providers and a future security policy engine can be introduced without redesigning the manifest architecture.

## 3. Application Manifest

Every application has its own manifest.

The manifest describes application metadata, execution preferences, persistence requirements, and requested resources.

A conceptual example:

```json
{
  "name": "chromium",
  "cli_name": "chromium",
  "version": "1.1.2",
  "image": "ravios-chromium:latest",
  "container": "chromium",
  "autostart": false,
  "resources": {
    "display": true,
    "gpu": true,
    "audio": true,
    "networks": [
      {
        "name": "ravios-browser",
        "mode": "shared"
      }
    ],
    "volumes": [
      {
        "name": "chromium-data",
        "target": "/data",
        "persistent": true
      },
      {
        "name": "chromium-cache",
        "target": "/cache",
        "persistent": true
      }
    ]
  }
}
```

This example illustrates the intended architecture. It is not a finalized or enforced manifest schema.

### Manifest responsibilities

The manifest declares:

- Which application resources are required.
- Which display environment the application needs.
- Whether GPU access is required.
- Whether audio access is required.
- Which named networks the application should join.
- Which persistent or temporary volumes it needs.
- Other supported devices and resources as the architecture expands.

### What the manifest must not contain

The manifest should not need to specify:

- Host numeric group IDs.
- Host-specific socket paths.
- Docker command-line arguments.
- Docker-specific device configuration.
- Host implementation details.
- Arbitrary shell commands to configure host resources.

These details belong to the runtime and its resource providers.

## 4. Generic Application Runtime

The RaviOS application runtime is responsible for interpreting manifests and preparing the execution environment.

Its responsibilities include:

1. Reading and validating an application's manifest.
2. Identifying the requested resources.
3. Resolving logical resource names to host resources.
4. Checking whether the requested resources can be provided.
5. Preparing mounts, devices, groups, environment variables, and networks.
6. Configuring the application's isolation and security settings.
7. Starting and managing the application.
8. Cleaning up application-specific resources when the application stops or is removed.

The runtime should use a modular resource-provider architecture.

For example:

| Resource provider | Responsibility |
| --- | --- |
| Display provider | Resolves display access and Wayland socket configuration |
| GPU provider | Resolves GPU devices and required group permissions |
| Audio provider | Resolves PipeWire access |
| Network provider | Creates and manages named application networks |
| Volume provider | Creates and manages application storage |
| Device provider | Handles additional supported host devices |

New providers should be added without introducing application-specific logic into the core runtime.

## 5. Resource Management

### 5.1 Display

Applications requesting:

```json
"display": true
```

receive access to the supported graphical display environment.

For the current RaviOS desktop architecture, this means Wayland access.

The display provider is responsible for resolving:

- The active Wayland display.
- The corresponding socket.
- The appropriate container mount.
- The required access permissions.

The manifest must not contain the actual host socket path.

### 5.2 GPU

Applications requesting:

```json
"gpu": true
```

receive access to the supported GPU devices.

The GPU provider is responsible for resolving the available devices, such as:

- `/dev/dri/card0`
- `/dev/dri/renderD128`

It also handles the required device permissions and group access.

GPU access is independent of display access. An application may require GPU acceleration without requiring a graphical display, or it may require a display without requiring direct GPU access.

### 5.3 Audio

Applications requesting:

```json
"audio": true
```

receive access to the supported audio environment.

For the current desktop architecture, the intended audio backend is PipeWire.

The audio provider resolves the relevant socket, mounts, environment variables, and access permissions.

Audio access must remain independent of display and GPU access.

### 5.4 Named Shared Networks

Applications can request named networks in their manifests.

For example, two applications may declare:

```json
{
  "name": "ravios-ai",
  "mode": "shared"
}
```

If Open WebUI and Ollama request the same shared network, the runtime must connect both applications to the same network.

The intended behavior is:

- If the named network already exists, reuse it.
- If it does not exist, create it.
- Connect the requesting application to it.
- Allow other applications requesting the same network to join it.
- Do not create duplicate networks for the same shared resource.
- Do not remove a shared network while other applications still depend on it.

Network lifecycle management must be based on resource ownership and active references, not on an individual application's lifecycle alone.

Stopping or removing one application must not accidentally disrupt other applications using the same shared network.

Applications can request different networks when isolation is required.

### 5.5 Volumes

Applications declare the storage they need.

The volume provider is responsible for:

- Creating application storage.
- Mounting storage at the requested container paths.
- Preserving persistent data across restarts.
- Distinguishing persistent data from temporary storage.
- Avoiding accidental deletion of persistent data during application removal.

The runtime should manage volumes independently of individual application launch scripts.

### 5.6 Future Resources

The resource architecture must be extensible to support additional capabilities, including:

- USB devices.
- Other hardware devices.
- Additional display interfaces.
- Additional audio interfaces.
- Other host services and resources.

New resources should follow the same declarative manifest model.

## 6. System Groups and Access Control

RaviOS uses dedicated logical groups to represent resource access.

The current naming decisions are:

| Group | Purpose |
| --- | --- |
| `ravios-display-group` | Access to the Wayland display socket |
| `ravios-gpu-group` | Logical access group for GPU resources |
| `ravios-audio-group` | Access to the audio environment |

### 6.1 Display Group

`ravios-display-group` represents permission to access the graphical display socket.

The display provider is responsible for ensuring the socket's ownership and permissions are compatible with the intended group-based access model.

The display group must not automatically grant GPU or audio access.

### 6.2 GPU Group

`ravios-gpu-group` represents the logical GPU resource in the RaviOS architecture.

The current implementation can use the existing Linux `video` group as its underlying system permission mechanism.

The GPU provider maps the logical GPU request to:

- The host's GPU devices.
- The appropriate device permissions.
- The host group or groups required for access.

This avoids requiring application manifests to know about Linux-specific group names or numeric GIDs.

A future implementation may introduce a dedicated host group if necessary, without changing the logical manifest interface.

### 6.3 Audio Group

`ravios-audio-group` represents access to the supported audio environment.

Its exact mapping and permissions are handled by the audio provider.

### 6.4 Group Resolution

Group names and numeric GIDs are host implementation details.

The runtime must resolve the required host groups and provide the appropriate supplementary group access to the application container.

The application image does not need to use the same group names as the host.

The runtime must not hardcode host GIDs in application manifests.

## 7. Manifest Authority and Future Security Policy

The current design treats the system manifest as the authoritative declaration of application requirements.

The system administrator is responsible for controlling and modifying application manifests.

If an application declares a supported resource and RaviOS can provide it, the runtime should fulfill the request.

This is the initial resource-management model.

### Future policy engine

A separate security policy engine may be introduced in the future.

Its responsibility would be to evaluate whether a declared resource request should be permitted.

For example:

- An application requests GPU access.
- The runtime identifies the request.
- A future policy engine evaluates the request.
- The runtime either grants or denies the resource.

The policy engine is not part of the current implementation scope.

However, the architecture must allow this additional authorization layer to be introduced without changing the fundamental manifest model.

The runtime should therefore keep resource declaration, resource resolution, and authorization as conceptually separate responsibilities.

## 8. Application Isolation and Security

Applications run in isolated environments using Docker containers.

The runtime is responsible for applying the appropriate security configuration.

The security baseline includes:

- Running applications as non-root users where supported.
- Enabling `no-new-privileges`.
- Dropping unnecessary Linux capabilities.
- Keeping Docker's seccomp filtering enabled.
- Avoiding unrestricted host privileges.
- Providing only explicitly requested devices and resources.
- Avoiding unnecessary host namespace sharing.
- Keeping application storage and resource access controlled.

### Chromium sandbox

Chromium must use its own User Namespace sandbox and must not rely on `--no-sandbox`.

The host kernel must support the required namespace and seccomp functionality.

The Docker seccomp configuration must narrowly allow the User Namespace operations Chromium needs without granting unrelated namespace operations or `CAP_SYS_ADMIN`.

The verified RaviOS configuration includes:

- Kernel User Namespace support enabled.
- Kernel seccomp and seccomp-filter support enabled.
- A custom Docker seccomp profile based on Docker Engine 28.5.2's default profile.
- Narrowly scoped rules for `unshare` and `clone` with `CLONE_NEWUSER`.
- Docker daemon configured to use the custom profile by default.

The following privileges must not be granted merely to make Chromium work:

- `CAP_SYS_ADMIN`
- `CAP_SYS_PTRACE`
- `seccomp=unconfined`
- `apparmor=unconfined`
- `--no-sandbox`

`--ipc=host` should also be avoided unless a concrete, verified requirement demonstrates that it is necessary.

AppArmor is not currently available in the RaviOS kernel configuration. It should not be assumed to provide protection until the required kernel support is implemented and verified.

## 9. Desktop User and Runtime Privileges

The current RaviOS desktop session runs as root.

This is an accepted current implementation decision.

The architecture does not require introducing a dedicated non-root desktop user at this stage.

The application runtime must still support running individual containers as non-root users and granting them only the requested resource access.

Host-side resource resolution and container-side permissions are separate concerns.

The runtime should not assume that the desktop session user and the application container user are identical.

## 10. Application Lifecycle

Application lifecycle management belongs to the generic runtime.

The intended lifecycle is:

1. Discover the application.
2. Read its manifest.
3. Validate its resource declarations.
4. Resolve and prepare the requested resources.
5. Prepare the container configuration.
6. Start the application.
7. Track its resource usage.
8. Stop the application when requested.
9. Release application-specific resources when no longer needed.
10. Preserve shared resources that are still in use by other applications.

Shared resources must have lifecycle management independent of individual applications.

For example, stopping Chromium must not remove a shared network that is also used by Open WebUI or Ollama.

## 11. Separation of Responsibilities

The architecture separates application declarations from host implementation.

| Component | Responsibility |
| --- | --- |
| Application manifest | Declares application requirements |
| Application runtime | Interprets manifests and manages execution |
| Resource providers | Resolve and prepare individual resource types |
| Docker Engine | Provides container execution and isolation |
| Host operating system | Provides kernel, devices, groups, sockets, and services |
| Future policy engine | Authorizes or denies resource requests |

Application-specific launch scripts should not become independent resource managers.

They should eventually delegate execution to the generic runtime.

## 12. Current Implementation Status

The following table distinguishes verified work from architectural decisions that still require implementation.

| Item | Status |
| --- | --- |
| Manifest-driven architecture | Architectural decision |
| Generic application runtime | Architectural direction; implementation requires review |
| Generic resource-provider model | Architectural decision |
| Separate display and GPU resources | Architectural decision |
| `ravios-display-group` naming | Decided |
| `ravios-gpu-group` naming | Decided |
| Existing Linux `video` group as current GPU permission mapping | Initial implementation decision |
| `ravios-audio-group` naming | Proposed logical naming |
| Named shared network behavior | Architectural decision |
| Persistent volume management | Existing application support; generic provider integration remains to be completed |
| Kernel User Namespace support | Implemented and verified |
| Custom Docker seccomp profile | Implemented and verified |
| Docker daemon default seccomp integration | Implemented and verified |
| Chromium User Namespace operation under the custom profile | Tested successfully |
| Chromium non-root execution without `--no-sandbox` | Still requires integration and verification |
| Generic manifest-driven resource allocation | Pending implementation |
| Future security policy engine | Future work |
| AppArmor kernel support | Not currently available |

## 13. Implementation Guidelines

When extending RaviOS, follow these rules:

1. Do not add Chromium-specific resource logic to the generic runtime.
2. Do not put host paths, GIDs, or Docker flags in application manifests.
3. Do not combine display, GPU, and audio into one implicit permission.
4. Do not remove shared resources merely because one application stops.
5. Do not grant additional privileges just to work around missing resource mappings.
6. Keep resource providers modular and independently maintainable.
7. Keep the manifest declarative and implementation-independent.
8. Make it possible to introduce a policy engine later.
9. Validate resource availability before starting an application.
10. Keep application lifecycle and resource lifecycle consistent.

## 14. Final Architectural Goal

RaviOS should provide a generic application execution platform in which applications declare what they need, and the operating system determines how to provide those resources safely.

An application should not need to know whether its display is implemented through Wayland, whether its GPU access uses a Linux `video` group, or whether its network is implemented through Docker.

It should only declare its requirements.

The runtime and resource providers handle the implementation.

**The manifest describes intent. The runtime resolves resources. The operating system provides them. A future policy engine may control authorization.**
