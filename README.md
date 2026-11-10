# RaviOS

**A minimal, Docker-based Developer Appliance for generic x86_64 hardware.**

RaviOS is an early-stage project exploring a small, purpose-built Linux system that boots directly into a Docker-based development environment. Its goal is to combine a lightweight host operating system with a local web dashboard and an integrated application manager.

> **Project status:** Planning and foundation stage. The architecture and implementation are evolving. RaviOS is not yet a usable operating system.

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
6. **Incremental engineering.** First prove a minimal bootable image; then add Docker, services, and the management interface.

## What belongs on the host?

The host is expected to contain the Linux kernel, a minimal userland and init system, networking and storage support, Docker Engine and its required components, and the system services needed to operate RaviOS.

Development runtimes such as Python, Node.js, and Go are **not planned as host installations**. They, along with databases and development tools, are intended to run as Docker containers.

Some optional management applications (for example, a container UI or monitoring service) may also run in containers.

## Planned architecture

See [Architecture Overview](docs/architecture/overview.md) for the current architectural outline, boundaries, assumptions, and unresolved decisions.

At a high level:

```text
Hardware (generic x86_64)
        |
Bootloader
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

## Build approach

RaviOS intends to use [Buildroot](https://buildroot.org/) with a project-owned **Buildroot External Tree**. This keeps RaviOS board configuration, package definitions, and filesystem customizations outside the upstream Buildroot source tree.

The Buildroot source checkout and generated build artifacts should normally remain outside the Git repository (or in ignored local directories). The repository should contain RaviOS-specific configuration and source code, not large generated toolchains or images.

## Development roadmap

The roadmap is intentionally staged:

1. **Bootable foundation:** Build a minimal x86_64 image and boot it in QEMU.
2. **Docker core:** Enable the kernel features and userspace components required by Docker; run a test container.
3. **System services:** Add boot orchestration, networking, SSH, logging, and persistent storage handling.
4. **Management interface:** Add the local dashboard and Docker integration.
5. **Application Manager:** Add a catalog and lifecycle operations for Docker-based applications.
6. **Images and hardware testing:** Produce installable images and test on representative x86_64 hardware.

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

This is a proposed starting layout, not a claim that all directories are implemented. We will add directories when their responsibilities and contents become concrete.

## Current non-goals

- A general-purpose desktop operating system.
- Installing every development language or database directly on the host.
- Supporting every CPU architecture in the first milestone.
- Exposing the Docker API or management dashboard publicly by default.
- Finalizing the application manifest format before the Application Manager requirements are understood.

## Contributing and project decisions

The project is at an early design stage. Significant architectural choices should be recorded in `docs/architecture/` (or a future architecture decision record directory) so that implementation remains consistent.

Before selecting a license, review the licensing obligations of the project and its dependencies. No license is declared by this initial documentation.

## License

**Not selected yet.** Until a license is added, do not assume that the repository is available for reuse, redistribution, or modification under an open-source license.
