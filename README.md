
# RaviOS

**A minimal, Docker-based Developer Appliance for generic x86_64 hardware.**

**We build Docker with Buildroot, then build an operating system to host it.**

RaviOS is an experimental, purpose-built Linux operating system designed to provide a lightweight host environment for Docker-based development workloads.

The long-term goal is to combine a minimal Linux system with Docker Engine, SSH access, a local web dashboard, and an integrated application manager.

RaviOS is built using Buildroot and maintained through a project-specific Buildroot External Tree.

> **Project status:** Early development. The initial x86_64 bootable system has been successfully built and tested in VirtualBox using UEFI. SSH access is operational. Docker Engine has been integrated into the Buildroot configuration, while persistent Docker storage and full runtime validation are still in progress.

## Project goals

**RaviOS — Nothing unnecessary. Everything intentional.**

- Target generic `x86_64` systems (Intel and AMD).
- Build a small, reproducible Linux image using Buildroot.
- Integrate Docker Engine into the operating system.
- Start Docker automatically during boot when its data storage is available.
- Keep language runtimes and development services in containers rather than installing them on the host.
- Provide SSH for system administration.
- Provide a local web dashboard for managing the appliance.
- Provide an Application Manager for discovering and managing supported Docker-based applications.
- Produce bootable disk images with selectable storage capacity.
- Support persistent Docker data independently of replaceable operating-system files.

## Design principles

**RaviOS isn't built to include everything. It's built to include exactly what it needs.**

1. **Small host, capable containers.** The host contains only what is needed to boot, operate, network, store data, and manage containers.
2. **Reproducible builds.** Build configuration and project-specific customizations are version-controlled.
3. **Modular applications.** Optional applications are managed independently of the operating-system core.
4. **Persistent user data.** Container data and application configuration must be kept separate from replaceable system files.
5. **Local-first management.** The web dashboard is intended to listen on loopback (`127.0.0.1`) by default.
6. **Portable Docker storage.** Docker data is designed to be reusable across compatible RaviOS installations.
7. **Incremental engineering.** Each major component is implemented and tested before moving to the next stage.

## Current implementation

The following table distinguishes implemented components from features that still require integration or runtime validation.

| Component | Status |
|---|---|
| Buildroot development environment | Implemented |
| Buildroot External Tree | Implemented |
| x86_64 Linux kernel build | Implemented |
| Linux kernel 7.3.3 | Integrated |
| BIOS boot configuration | Implemented |
| UEFI boot configuration | Implemented |
| GRUB 2 bootloader | Implemented |
| UEFI bootable disk image | Tested in VirtualBox |
| Configurable disk image size | Implemented in build tooling |
| Root account and password authentication | Implemented |
| SSH server (Dropbear) | Implemented |
| SSH access from Windows host | Tested |
| Docker Engine Buildroot integration | Implemented |
| Docker Engine runtime | Validation in progress |
| Docker Data partition | Initial integration; storage workflow in progress |
| Persistent Docker storage selection | Planned / in development |
| Local web dashboard | Planned |
| Application Manager | Planned |

### Current system configuration

- Build system: Buildroot `2026.08.1`
- Linux kernel: `7.3.3`
- Architecture: `x86_64`
- Bootloader: GRUB 2
- Boot modes: BIOS and UEFI configurations
- Init system: BusyBox init
- Device management: eudev
- SSH server: Dropbear
- Root filesystem: ext filesystem image
- Container engine: Docker Engine `28.5.2`
- Image generation: Genimage `20`
- Development environment: Docker Desktop
- Current test environment: VirtualBox

The current system is intentionally minimal. Its initial implementation focuses on a reliable boot process, basic networking, root access, remote administration, and integration of the Docker runtime.

## Docker and persistent storage

Docker is a central part of RaviOS rather than an optional application installed after the operating system has booted.

The Docker Engine package and its dependencies are integrated into the Buildroot configuration.

A dedicated storage area is being developed for Docker's persistent data.

The intended design separates:

- **System storage:** The operating system, kernel, bootloader, and system configuration.
- **Docker Data:** Container images, writable layers, volumes, and other Docker-managed data.

Docker Data is intended to use ext4 and mount at:

```text
/var/lib/docker
```

The long-term storage design aims to make Docker Data independent of a particular RaviOS installation. This allows compatible installations to reuse the same Docker storage device.

The intended management workflow will support:

- Identifying available Docker Data storage.
- Inspecting existing storage before using it.
- Selecting an external Docker Data device.
- Switching between Docker Data locations.
- Returning to the internal storage when an external device is unavailable.
- Explicitly resetting storage when requested.

An existing external Docker Data filesystem must never be formatted automatically.

The storage selection and recovery workflow is still under development. The exact partition sizing, filesystem initialization, and switching behavior will be documented after implementation and testing.

## What belongs on the host?

The host is expected to contain:

- Linux kernel and a minimal userland.
- Init system and essential system services.
- Networking and storage support.
- Docker Engine and its required components.
- SSH server.
- Services required to operate RaviOS.

Development runtimes such as Python, Node.js, and Go are **not planned as host installations**. They, along with databases and development tools, are intended to run as Docker containers.

Some optional management applications, such as container interfaces and monitoring services, may also run in containers.

## Planned architecture

See [Architecture Overview](docs/architecture/overview.md) for the current architectural outline, boundaries, assumptions, and unresolved decisions.

At a high level:

```text
Hardware (generic x86_64)
        |
Bootloader (GRUB 2)
        |
Linux kernel
        |
Minimal host userspace and init
        |
Network / storage / system services
        |
Docker Data storage
        |
Docker Engine
        |
Application Manager + optional application containers
        |
Local Web Dashboard (127.0.0.1 by default)
```

The architecture is intentionally layered. The operating-system core provides the foundation, while development environments and optional applications are managed through Docker.

## Build environment

RaviOS uses [Buildroot](https://buildroot.org/) with a project-owned **Buildroot External Tree**.

The development environment is provided through Docker, keeping the build toolchain and dependencies separate from the host operating system.

The project separates the following build resources:

- Buildroot source tree.
- Build output and generated target filesystem.
- Downloaded source archives.
- Compiler cache.
- RaviOS-specific configuration and customizations.
- Generated disk images and other artifacts.

Buildroot source files and generated build resources are kept outside the Git repository where appropriate. The repository contains project-specific configuration, scripts, and source code rather than large generated toolchains or images.

### Build requirements

The current development workflow uses:

- Windows with PowerShell.
- Docker Desktop with Docker Compose.
- Git.
- VirtualBox for virtual-machine testing.

The build environment is containerized. Buildroot source, output, download cache, and compiler cache are stored in Docker-managed Linux volumes rather than Windows filesystem bind mounts. This improves build performance and preserves Linux filesystem behavior.

### Building RaviOS

From the project root, run:

```powershell
.\build.ps1
```

The default disk image size is 16 GB.

To select a different disk capacity:

```powershell
.\build.ps1 -DiskSize 5G
```

For example, a larger image can be generated with:

```powershell
.\build.ps1 -DiskSize 32G
```

The build script coordinates the build process and disk image generation.

For additional information about the development environment, dependencies, and manual package downloads, see:

[Build Environment](docs/development/build-environment.md)

## Project file handling

RaviOS uses Linux-style line endings (`LF`) for text files throughout the repository.

The repository includes a PowerShell utility to normalize line endings:

```powershell
.\normalize-line-endings.ps1
```

The script:

- Normalizes text files to LF.
- Preserves binary files.
- Processes tracked files and non-ignored untracked files.
- Configures repository-local Git line-ending settings.
- Checks tracked files after normalization.

A dry run is available:

```powershell
.\normalize-line-endings.ps1 -WhatIf
```

Generated artifacts, local backups, and temporary files are excluded from Git through `.gitignore`.

## Development roadmap

The roadmap is intentionally staged.

### 1. Bootable foundation — Implemented

- Build a minimal x86_64 Linux image.
- Configure GRUB and BIOS/UEFI boot support.
- Generate bootable disk images.
- Boot and test the UEFI image in VirtualBox.
- Establish root login and SSH access.
- Create a reproducible Docker-based build environment.

### 2. Docker core — In progress

- Enable the required kernel features.
- Integrate Docker Engine and its dependencies.
- Complete Docker daemon startup and runtime validation.
- Configure container storage and networking.
- Run and validate test containers.

### 3. Persistent storage and system services — In progress

- Define the internal Docker Data partition.
- Generate and initialize the Docker Data filesystem during image creation.
- Implement storage discovery and validation.
- Support external Docker Data devices.
- Implement explicit storage selection and switching.
- Improve boot orchestration and logging.

### 4. Management interface — Planned

- Develop a local web dashboard.
- Integrate dashboard operations with Docker.
- Keep management interfaces local by default.
- Provide basic system and container monitoring.

### 5. Application Manager — Planned

- Define an application catalog and manifest format.
- Implement application installation, configuration, and lifecycle management.
- Support independently managed Docker-based applications.

### 6. Images and hardware testing — Planned

- Improve disk image generation.
- Continue BIOS and UEFI compatibility testing.
- Explore ISO support where appropriate.
- Test on representative x86_64 hardware.
- Validate storage portability across multiple RaviOS installations.

## Repository layout

The current repository contains the following main components:

```text
RaviOS/
├── .devcontainer/
├── buildroot-external/
│   ├── external.desc
│   ├── external.mk
│   ├── Config.in
│   ├── configs/
│   ├── board/
│   ├── package/
│   └── rootfs-overlay/
├── docker/
│   └── development/
│       └── Dockerfile
├── docs/
│   ├── architecture/
│   │   └── overview.md
│   └── development/
│       ├── build-environment.md
│       └── git-workflow.md
├── build.ps1
├── normalize-line-endings.ps1
├── docker-compose.yml
├── .gitattributes
├── .gitignore
├── README.md
└── overview.md
```

Generated images, VirtualBox files, build outputs, and local temporary files are not part of the source repository.

Future components such as the web dashboard, application catalog, and automated tests will be introduced when their responsibilities and interfaces become concrete.

## Current non-goals

- A general-purpose desktop operating system.
- Installing every development language or database directly on the host.
- Supporting every CPU architecture in the first milestone.
- Exposing the Docker API or management dashboard publicly by default.
- Finalizing the application manifest format before the Application Manager requirements are understood.
- Automatically formatting or modifying existing external Docker Data storage.

## Contributing and project decisions

RaviOS is being developed incrementally. Contributions and independent development are encouraged.

Significant architectural choices should be documented in `docs/architecture/` (or a future architecture decision record directory) so that implementation remains consistent.

The current development image uses a default root password (`ravios`). This is intended for initial development and testing. Change it before using the system in an environment where the default credentials could be exposed.

Before selecting a license, review the licensing obligations of the project and its dependencies. No license is declared by this documentation.

See [Git Workflow](docs/development/git-workflow.md) for branching conventions, milestone tags, and development practices.

## Documentation

- [Architecture Overview](docs/architecture/overview.md) — System architecture, design boundaries, and technical decisions.
- [Build Environment](docs/development/build-environment.md) — Build setup, Docker volumes, download cache management, and manual package downloads.
- [Git Workflow](docs/development/git-workflow.md) — Branching, commits, tags, and development practices.

## License

**Not selected yet.**

Until a license is added, do not assume that the repository is available for reuse, redistribution, or modification under an open-source license.
