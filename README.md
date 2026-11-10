
# RaviOS

**A minimal, Docker-based Developer Appliance for generic x86_64 hardware.**

RaviOS is an experimental, purpose-built Linux operating system designed to provide a lightweight host environment for Docker-based development workloads.

The long-term goal is to combine a minimal Linux system with Docker Engine, SSH access, a local web dashboard, and an integrated application manager.

RaviOS is built using Buildroot and maintained through a project-specific Buildroot External Tree.

> **Project status:** Early development. The initial x86_64 bootable system has been built and successfully tested in VirtualBox. SSH access is operational. Docker Engine and the higher-level management components are still under development.

## Project goals

- Target generic `x86_64` systems (Intel and AMD).
- Build a small, reproducible Linux image using Buildroot.
- Start Docker automatically during boot.
- Keep language runtimes and development services in containers rather than installing them on the host.
- Provide SSH for system administration.
- Provide a local web dashboard for managing the appliance.
- Provide an Application Manager for discovering and managing supported Docker-based applications.
- Produce bootable disk images, with ISO support where appropriate.

## Design principles

1. **Small host, capable containers.** The host contains only what is needed to boot, operate, network, store data, and manage containers.
2. **Reproducible builds.** Build configuration and project-specific customizations are version-controlled.
3. **Modular applications.** Optional applications are managed independently of the operating-system core.
4. **Persistent user data.** Container data and application configuration must be kept separate from replaceable system files.
5. **Local-first management.** The web dashboard is intended to listen on loopback (`127.0.0.1`) by default.
6. **Incremental engineering.** Each major component is implemented and tested before moving to the next stage.

## Current implementation

The following components have been implemented and tested:

| Component | Status |
|---|---|
| Buildroot development environment | Implemented |
| Buildroot External Tree | Implemented |
| x86_64 Linux kernel build | Implemented |
| BIOS bootloader (GRUB) | Implemented |
| Bootable disk image | Tested in VirtualBox |
| Root account and password authentication | Implemented |
| SSH server (Dropbear) | Tested |
| SSH access from Windows host | Tested |
| Docker Engine | Not implemented |
| Persistent application storage | Planned |
| Local web dashboard | Planned |
| Application Manager | Planned |

### Current system configuration

- Build system: Buildroot `2026.08.1`
- Linux kernel: `7.3.3`
- Architecture: `x86_64`
- Boot mode: BIOS
- Bootloader: GRUB
- Init system: BusyBox init
- SSH server: Dropbear
- Root filesystem: ext2
- Development environment: Docker Desktop
- Current test environment: VirtualBox

The current system is intentionally minimal. Its initial implementation focuses on a reliable boot process, basic networking, root access, and remote administration.

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
Bootloader (GRUB)
         |
Linux kernel
         |
Minimal host userspace and init
         |
Network / storage / system services
         |
Docker Engine
         |
Application Manager + optional application containers
         |
Local Web Dashboard (127.0.0.1 by default)
```

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

## Development roadmap

The roadmap is intentionally staged:

1. **Bootable foundation — Completed.**
   - Build a minimal x86_64 Linux image.
   - Configure GRUB and BIOS boot.
   - Boot and test the image in VirtualBox.
   - Establish root login and SSH access.

2. **Docker core — In progress.**
   - Enable the required kernel features.
   - Integrate Docker Engine and its dependencies.
   - Configure container storage and networking.
   - Run and validate test containers.

3. **System services.**
   - Improve boot orchestration.
   - Configure persistent storage.
   - Integrate essential system services and logging.

4. **Management interface.**
   - Develop a local web dashboard.
   - Integrate dashboard operations with Docker.
   - Keep management interfaces local by default.

5. **Application Manager.**
   - Define an application catalog and manifest format.
   - Implement application installation, configuration, and lifecycle management.
   - Support independently managed Docker-based applications.

6. **Images and hardware testing.**
   - Improve disk image generation.
   - Explore ISO support where appropriate.
   - Test on representative x86_64 hardware.

## Repository layout

```text
RaviOS/
├── buildroot-external/
│   ├── external.desc
│   ├── external.mk
│   ├── Config.in
│   ├── configs/
│   ├── board/
│   └── package/
├── docs/
│   └── architecture/
│       └── overview.md
├── applications/
│   └── catalog/
├── web/
│   ├── dashboard/
│   └── application-manager/
├── system/
├── scripts/
└── tests/
```

This layout describes the intended project organization. Some directories represent planned components and will be introduced as their responsibilities become concrete.

## Current non-goals

- A general-purpose desktop operating system.
- Installing every development language or database directly on the host.
- Supporting every CPU architecture in the first milestone.
- Exposing the Docker API or management dashboard publicly by default.
- Finalizing the application manifest format before the Application Manager requirements are understood.

## Contributing and project decisions

RaviOS is being developed incrementally. Contributions and independent development are encouraged.

Significant architectural choices should be documented in `docs/architecture/` (or a future architecture decision record directory) so that implementation remains consistent.

The current development image uses a default root password (`ravios`). This is intended for initial development and testing. Change it before using the system in an environment where the default credentials could be exposed.

Before selecting a license, review the licensing obligations of the project and its dependencies. No license is declared by this documentation.

## License

**Not selected yet.**

Until a license is added, do not assume that the repository is available for reuse, redistribution, or modification under an open-source license.
