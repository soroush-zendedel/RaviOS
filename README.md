# RaviOS

**A minimal, Docker-based Developer Appliance for generic x86_64 hardware.**

**We build Docker with Buildroot, then build an operating system to host it.**

RaviOS is an experimental, purpose-built Linux operating system designed to provide a lightweight host environment for Docker-based development workloads.

The long-term goal is to combine a minimal Linux system with Docker Engine, SSH access, a local web dashboard, and an integrated application manager.

RaviOS is built using Buildroot and maintained through a project-specific Buildroot External Tree.

> **Project status:** Early development. The initial x86_64 system boots successfully in VirtualBox using UEFI, and SSH access is operational. Docker Engine is integrated and has successfully pulled and run test containers. Docker Data supports both internal and external storage, automatic discovery, persistent selection, and switching between storage devices. Both image build modes—with and without an internal Docker Data partition—have been tested. BIOS compatibility and broader physical hardware validation remain ongoing.

## Project goals

**RaviOS — Nothing unnecessary. Everything intentional.**

- Target generic `x86_64` systems (Intel and AMD).
- Build a small, reproducible Linux image using Buildroot.
- Integrate Docker Engine into the operating system.
- Start Docker automatically during boot only when its data storage is available.
- Keep language runtimes and development services in containers rather than installing them on the host.
- Provide SSH for system administration.
- Provide a local web dashboard for managing the appliance.
- Provide an Application Manager for discovering and managing supported Docker-based applications.
- Produce bootable disk images with selectable storage capacity.
- Keep persistent Docker data separate from replaceable operating-system files.

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
| BIOS boot configuration | Configured; runtime testing pending |
| UEFI boot configuration | Implemented |
| GRUB 2 bootloader | Implemented |
| UEFI bootable disk image | Tested in VirtualBox |
| Configurable disk image size | Implemented in build tooling |
| Root account and password authentication | Implemented |
| SSH server (Dropbear) | Implemented |
| SSH access from Windows host | Tested |
| Docker Engine Buildroot integration | Implemented |
| Docker daemon startup | Tested |
| Docker container execution (`hello-world`) | Tested successfully |
| Docker image download from Docker Hub | Tested successfully |
| Dedicated Docker Data ext4 partition | Implemented |
| Docker Data mount at `/var/lib/docker` | Tested |
| Docker image persistence across reboot | Tested |
| Image build without an internal Docker Data partition | Tested |
| Missing Docker Data startup protection | Tested |
| External Docker Data discovery and reuse | Tested |
| Persistent explicit storage selection | Tested |
| Switching between internal and external Docker Data | Tested |
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
- Container storage driver: `overlay2`
- Cgroup mode: cgroup v2
- Docker Data filesystem: ext4
- Docker Data mount point: `/var/lib/docker`
- Image generation: Genimage `20`
- Development environment: Docker Desktop
- Current test environment: VirtualBox

The current system is intentionally minimal. Its initial implementation focuses on a reliable boot process, basic networking, root access, remote administration, and a working Docker runtime.

## Docker and persistent storage

Docker is a central part of RaviOS rather than an optional application installed after the operating system has booted.

The Docker Engine package and its dependencies are integrated into the Buildroot configuration. The kernel configuration includes the features required by the current Docker runtime.

### Docker Data architecture

Docker uses a dedicated ext4 filesystem mounted at:

```text
/var/lib/docker
```

The storage architecture separates:

- System storage: The operating system, kernel, bootloader, and system configuration.
- Docker Data: Container images, writable layers, volumes, and other Docker-managed data.

Docker Data is validated using its designated filesystem UUID and filesystem label. The partition label `docker-data` is used as an additional discovery identifier, but is not mandatory. Explicit storage selections are persisted using stable disk identifiers and PARTUUID values, allowing RaviOS to locate the selected partition independently of device names.

### Image build modes

The build system supports two modes:

- Create: Generates an internal Docker Data partition as part of the disk image. The partition uses the remaining available disk capacity.
- None: Generates an image containing only the EFI and RootFS partitions, without reserving space for internal Docker Data.

In both modes, RaviOS can discover an existing compatible Docker Data filesystem on the boot disk or an external disk.

If no valid Docker Data storage is available, Docker does not start and does not fall back to storing its data in the RootFS.

### Storage discovery and management

RaviOS supports:

- Automatic discovery of valid Docker Data partitions.
- Boot-disk priority when selecting storage automatically.
- Reuse of existing external Docker Data filesystems.
- Persistent explicit selection using stable disk and partition identifiers.
- Interactive switching between valid Docker Data destinations.
- Status reporting and candidate listing.
- Returning to automatic discovery by clearing an explicit selection.

Existing Docker Data filesystems are never formatted as part of automatic discovery or storage switching.

### Validation

The current implementation has been tested by:

- Building images with and without an internal Docker Data partition.
- Booting both image types in VirtualBox.
- Confirming that Docker remains stopped when storage is unavailable.
- Pulling and running the `hello-world` container.
- Rebooting and confirming Docker image persistence.
- Discovering and reusing an external Docker Data filesystem.
- Confirming automatic boot-disk priority.
- Persisting an explicit external storage selection across reboot.
- Switching between internal and external Docker Data.
- Confirming that containers remain available on their respective storage devices.

For build parameters, storage behavior, management commands, and detailed validation results, see:

[Docker Engine Integration](docs/development/docker-engine.md)

## What belongs on the host?

The host is expected to contain:

- Linux kernel and a minimal userland.
- Init system and essential system services.
- Networking and storage support.
- Docker Engine and its required components.
- SSH server.
- Services required to operate RaviOS.

Development runtimes such as Python, Node.js, and Go are not planned as host installations. They, along with databases and development tools, are intended to run as Docker containers.

Some optional management applications, such as container interfaces and monitoring services, may also run in containers.

## Planned architecture

See [Architecture Overview](docs/architecture/overview.md) for the current architectural outline, boundaries, assumptions, and unresolved decisions.

At a high level:

```
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

RaviOS uses [Buildroot](https://buildroot.org/) with a project-owned Buildroot External Tree.

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

```
.\build.ps1
```

The default configuration creates an internal Docker Data partition and uses a default disk image size of 16 GB.

To select a different disk capacity:

```
.\build.ps1 -DockerData Create -DiskSize 6G
```

To build an image without an internal Docker Data partition:

```
.\build.ps1 -DockerData None
```

In `None` mode, the image size is calculated automatically from the required partitions. No additional disk capacity is reserved for Docker Data.

For additional information about the development environment, dependencies, and manual package downloads, see:

[Build Environment](docs/development/build-environment.md)

For Docker integration and storage configuration, see:

[Docker Engine Integration](docs/development/docker-engine.md)

## Project file handling

RaviOS uses Linux-style line endings (`LF`) for text files throughout the repository.

The repository includes a PowerShell utility to normalize line endings:

```
.\normalize-line-endings.ps1
```

The script:

- Normalizes text files to LF.
- Preserves binary files.
- Processes tracked files and non-ignored untracked files.
- Configures repository-local Git line-ending settings.
- Checks tracked files after normalization.

A dry run is available:

```
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

### 2. Docker core — Implemented

- Enable the required kernel features.
- Integrate Docker Engine and its dependencies.
- Configure Docker daemon startup.
- Configure container storage and networking.
- Pull and run test containers successfully.
- Validate Docker runtime behavior in VirtualBox.

### 3. Persistent storage and system services — Core implementation completed

- Define and generate the internal Docker Data partition.
- Support image generation with and without internal Docker Data.
- Initialize the Docker Data ext4 filesystem with its designated identity.
- Mount Docker Data at `/var/lib/docker`.
- Verify persistence across reboot.
- Prevent Docker startup when valid Docker Data storage is unavailable.
- Discover and reuse external Docker Data filesystems.
- Support persistent explicit storage selection.
- Implement interactive switching between storage destinations.
- Validate internal and external storage switching.

Further hardware testing and additional failure-recovery validation remain ongoing.

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

```
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
│       ├── docker-engine.md
│       ├── git-workflow.md
│       └── kernel-config-reproducibility-issue.md
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
- Silently storing Docker data in the RootFS when the dedicated Docker Data storage is unavailable.

## Contributing and project decisions

RaviOS is being developed incrementally. Contributions and independent development are encouraged.

Significant architectural choices should be documented in `docs/architecture/` (or a future architecture decision record directory) so that implementation remains consistent.

The current development image uses a default root password (`ravios`). This is intended for initial development and testing. Change it before using the system in an environment where the default credentials could be exposed.

Before selecting a license, review the licensing obligations of the project and its dependencies. No license is declared by this documentation.

See [Git Workflow](docs/development/git-workflow.md) for branching conventions, milestone tags, and development practices.

## Documentation

- [Architecture Overview](docs/architecture/overview.md) — System architecture, design boundaries, and technical decisions.
- [Build Environment](docs/development/build-environment.md) — Build setup, Docker volumes, download cache management, and manual package downloads.
- [Docker Engine](docs/development/docker-engine.md) — Docker integration, kernel requirements, runtime validation, and persistent data storage.
- [Kernel Configuration Reproducibility Issue](docs/development/kernel-config-reproducibility-issue.md) — Problem statement and proposed work for making kernel configuration reproducible.
- [Git Workflow](docs/development/git-workflow.md) — Branching, commits, tags, and development practices.

## License

Not selected yet.

Until a license is added, do not assume that the repository is available for reuse, redistribution, or modification under an open-source license.
