# RaviOS Native Desktop GUI Manual

**Document status:** Development plan; implementation not started  
**Target branch:** `develop/native-desktop-niri`  
**Base branch:** `main`  
**Target platform:** Generic x86_64 hardware  
**Desktop compositor:** Niri (planned; not yet integrated)

> This document is the working technical manual for the native desktop effort. It records verified facts from the current `main` branch separately from proposals and decisions that still require testing. Update it whenever implementation changes the architecture or invalidates an assumption.

## 1. Goal and scope

Add an optional native Wayland desktop environment to RaviOS, with Niri as the planned compositor. The desktop stack belongs to the host operating system and is installed in the Buildroot-generated RootFS.

The desktop must be independent of Docker Engine, Docker Data storage, and Ollama. A missing, disabled, or failed Docker service must not prevent the host from booting to a usable desktop. Likewise, the desktop must not require Docker or an Ollama container to start.

This branch is for the native desktop foundation. Docker/Ollama integration is a later, explicit integration task on a shared branch after the independent branches have been developed and reviewed.

### In scope

- Native Wayland session and Niri compositor in RootFS.
- Required graphics, input, seat/session, font, and desktop runtime dependencies.
- Reliable startup and shutdown using the existing RaviOS init/service conventions unless evidence supports a change.
- A deliberate choice between desktop startup and headless/server operation.
- Basic desktop usability and diagnostic documentation.
- Build-size, boot, graphics, input, and failure-mode validation.

### Out of scope for the initial desktop milestone

- Running Niri or the compositor inside Docker.
- Making Docker a prerequisite for the desktop.
- Making Ollama a prerequisite for the desktop.
- A full application store or application manager redesign.
- A complete display manager/login manager unless a prototype demonstrates it is necessary.
- Automatic graphics-driver support for every x86_64 GPU without a defined and tested hardware matrix.

## 2. Existing RaviOS baseline (from `main`)

The following are present in the inspected `main` source tree; their presence does not prove runtime functionality on physical hardware.

### Build and operating-system structure

- Buildroot is used through the RaviOS external tree at `buildroot-external/`.
- The x86_64 defconfig is `buildroot-external/configs/ravios_x86_64_defconfig`.
- The custom Linux configuration is `buildroot-external/board/ravios/x86_64/linux.config`.
- The RootFS overlay is `buildroot-external/rootfs-overlay/`.
- The configured RootFS ext4 image size is currently `1024M`.
- The root filesystem overlay currently contains BusyBox-style init scripts for Docker Data and Docker Engine: `S50docker-data` and `S60dockerd`.
- `post-build.sh` currently sets executable permissions for those scripts and copies the GRUB configuration files.

### Existing kernel graphics/input options

The current kernel config includes:

- `CONFIG_INPUT_EVDEV=y`
- `CONFIG_DRM=y`
- `CONFIG_DRM_I915=y`
- `CONFIG_DRM_QXL=y`
- `CONFIG_DRM_BOCHS=y`
- `CONFIG_DRM_VIRTIO_GPU=y`
- `CONFIG_FB=y`
- `CONFIG_FB_VESA=y`
- `CONFIG_FB_EFI=y`
- `CONFIG_VIRTIO_INPUT=y`

These options are only a starting point. They do not establish that a Wayland session can start, that a GPU is accelerated, or that the target hardware is supported. AMDGPU, Nouveau, firmware requirements, KMS behavior, and other device-specific requirements must be assessed against the actual hardware support goals.

### Known gaps in the current baseline

The inspected defconfig does not currently enable an identified complete Wayland/Niri desktop stack. The current overlay has no desktop session startup service. The available source snapshot does not establish that the selected Buildroot revision provides a directly usable Niri package or all of its dependencies.

## 3. Architecture and service boundaries

The host operating system owns physical hardware and the interactive desktop session:

- Kernel DRM/KMS and input device drivers.
- Device nodes and permissions.
- Seat/session access and VT handling.
- Wayland compositor (Niri).
- Display/session startup and shutdown.
- Native host utilities needed for the desktop.

Docker owns containerized application workloads. Containers may optionally be granted access to a running host Wayland session in a later integration phase, but they do not own the compositor or physical display session.

Ollama remains an optional application workload/service and is not part of desktop startup dependencies.

### Independence requirements

1. The desktop startup path must not call Docker commands or wait for `dockerd`.
2. The desktop startup path must not require Docker Data to be mounted.
3. The desktop startup path must not wait for or invoke Ollama.
4. Docker startup failures must not stop or restart the desktop session.
5. Desktop startup failures must be diagnosable and must not corrupt Docker Data.
6. Headless mode must remain possible without starting a compositor.

## 4. Boot and session modes

A supported operating mode must be selected and documented before implementing automatic desktop startup.

Proposed modes:

- **Desktop mode:** starts the native graphical session on the intended local console.
- **Headless/server mode:** boots the host services without starting a compositor.

The configuration mechanism is TBD. Candidates include a simple RaviOS configuration file or an explicit kernel/boot argument. Do not hard-code an unchangeable desktop start into the boot path before this decision is tested.

The desktop service should start only after the kernel has exposed the required DRM/input devices and the chosen seat/session mechanism is ready. Exact ordering must follow the selected userspace components and be validated on target hardware.

## 5. Technology selection and dependency investigation

Niri is a Rust-based Wayland compositor. Its actual Buildroot integration method and dependency versions must be verified against the exact Buildroot revision used by RaviOS before implementation.

Investigate and document at least:

- Niri source version/release and license.
- Whether a suitable Buildroot package exists in the pinned Buildroot tree; if not, whether a RaviOS package recipe is maintainable.
- Rust host/target toolchain support and cross-compilation requirements.
- Wayland server/protocol dependencies.
- Smithay and other compositor dependencies required by the selected Niri version.
- `libinput`, `libxkbcommon`, seat/session management (for example, `seatd` or an alternative), and required udev/device management.
- EGL/OpenGL/Mesa requirements and the supported software-rendering fallback, if any.
- Fontconfig, fonts, terminal, launcher, and other minimum session utilities.
- Kernel firmware requirements for the intended GPU families.

Do not assume package names, Buildroot symbols, versions, or dependency availability from another Buildroot release. Verify them in RaviOS's actual Buildroot source and record the evidence.

### Dependency decision table

| Component | Purpose | Decision/status |
|---|---|---|
| Niri | Wayland compositor | Planned; package strategy TBD |
| Wayland protocols/libraries | Wayland client/server interfaces | TBD; verify exact dependency graph |
| Smithay | Compositor framework used by Niri | Version/dependency TBD |
| libinput | Input device handling | TBD |
| libxkbcommon | Keyboard keymap handling | TBD |
| seat/session manager | Secure access to input/DRM devices and VT | TBD; compare supported options |
| Mesa/EGL/GBM | GPU userspace graphics stack | TBD; hardware-dependent |
| Fonts/fontconfig | Text rendering | TBD |
| Terminal | Basic interactive shell | TBD |
| Launcher | Starting applications | TBD |
| Status bar/panel | Desktop status/navigation | Optional; TBD |

## 6. Buildroot integration rules

- Keep RaviOS-specific package recipes and configuration in `buildroot-external/`; do not patch the upstream Buildroot tree manually as the only record of a change.
- Prefer Buildroot packages and dependency declarations over ad-hoc downloads in `post-build.sh`.
- Use pinned, reproducible source versions and verified hashes where required by Buildroot package conventions.
- Separate host build tools from target runtime packages.
- Enable only the kernel options and firmware needed by the documented hardware support target.
- Keep desktop packages selectable through RaviOS configuration rather than silently making a desktop mandatory for every future image type, if the existing build design allows it.
- Update `post-build.sh` only for tasks that belong in the post-build phase; package installation and service configuration should use normal Buildroot mechanisms where practical.
- Regenerate and inspect `docs/system-inventory.md` after package/configuration changes. The inventory describes build contents, not proof of runtime operation.

## 7. RootFS and disk image impact

The current defconfig sets the RootFS ext4 size to `1024M`. A desktop stack can materially increase the image size through Rust binaries, graphics libraries, fonts, and utilities.

Before increasing the RootFS size, measure the actual generated target and image sizes. Review `post-image.sh` and the genimage layouts to understand how the RootFS partition size interacts with the Docker Data partition and requested disk size.

Requirements:

- Do not reduce Docker Data capacity unintentionally.
- Do not assume the existing 1 GiB RootFS is sufficient.
- Do not choose a new fixed size without a measured package footprint and reasonable growth margin.
- Test both Docker Data build modes supported by RaviOS, including `None` where applicable.
- Record the before/after RootFS size and the resulting Docker Data capacity for representative image sizes.

## 8. Session startup and process management

The current system uses numbered scripts under `rootfs-overlay/etc/init.d/`. The desktop service should follow the existing service convention unless a technical requirement justifies a different supervisor/session launcher.

The exact service name, runlevel ordering, user account, environment, VT handling, and restart policy are TBD until the compositor and seat/session design is selected.

The implementation must define:

- Which user owns the graphical session (avoid running the compositor as root unless a documented technical requirement makes it unavoidable).
- How the user is authenticated or automatically logged in, if applicable.
- How DRM/input access is granted.
- How the Wayland runtime directory and socket permissions are created.
- How the compositor receives the correct environment and VT.
- How clean shutdown and signal handling work.
- What happens if Niri exits or fails to initialize.
- How logs are captured and retrieved from a failed graphical boot.

Do not add a service script until these decisions are grounded in the selected runtime components.

## 9. Docker GUI application integration (later phase)

A future integration may allow selected trusted containers to display windows through the host Wayland compositor.

Potential mechanism: pass the host Wayland socket and the minimum required environment into a container. This is not enabled by this branch's initial desktop foundation.

Security requirements for that later work:

- Do not mount the Wayland socket into every container by default.
- Treat access to the Wayland socket as access to the user's graphical session; evaluate the security implications for the selected compositor/protocols.
- Grant access only to explicitly trusted applications.
- Do not expose the Docker socket to GUI containers merely because they use Wayland.
- Keep container GUI failures isolated from the host compositor and other containers.
- Document UID/GID, runtime directory, socket, environment, and lifecycle handling.

## 10. Implementation milestones

### Milestone 0 — Baseline and feasibility

- Confirm exact Buildroot revision and package tree used by the build container.
- Inspect existing kernel config, rootfs overlay, init scripts, and image sizing.
- Verify Niri's current build dependencies and license.
- Decide target GPU/hardware support and whether QEMU is an initial test target.
- Produce a dependency and feasibility report before package changes.

**Exit criteria:** A documented, reproducible package strategy and a list of required kernel/userspace changes.

### Milestone 1 — Minimal graphics foundation

- Add only the required kernel, firmware, seat, input, and graphics userspace components.
- Build the image and inspect package/RootFS size.
- Validate DRM/KMS and input device discovery on the chosen test target.

**Exit criteria:** Required devices and graphics interfaces are available; no compositor is required yet.

### Milestone 2 — Niri proof of concept

- Integrate Niri using the verified package strategy.
- Start it manually or through a controlled test session before enabling automatic boot startup.
- Validate keyboard, pointer, display modes, VT switching, and clean exit.
- Capture logs and document unsupported hardware/fallback behavior.

**Exit criteria:** A reproducible Niri session starts and operates on the declared test hardware.

### Milestone 3 — RaviOS desktop boot mode

- Implement the selected desktop/headless mode mechanism.
- Add the session startup service and required user/session setup.
- Verify that Docker and Docker Data are not startup dependencies.
- Verify graceful behavior when the compositor fails.

**Exit criteria:** Desktop and headless modes both boot as documented; Docker can be absent or disabled without blocking desktop startup.

### Milestone 4 — Minimum usable desktop

- Add a terminal and a minimal application-launching workflow.
- Add fonts and essential user configuration.
- Decide whether a panel/status bar, file manager, settings UI, or browser belongs in the first usable image.
- Keep optional applications modular where practical.

**Exit criteria:** A user can reach a usable shell/terminal and launch the documented minimum set of native applications.

### Milestone 5 — Hardening and integration readiness

- Test repeated boots, clean shutdown, compositor crashes, missing display, and headless boot.
- Measure image footprint and Docker Data capacity.
- Document hardware compatibility and known limitations.
- Prepare explicit integration notes for the future shared branch.

**Exit criteria:** Desktop branch is independently buildable and testable, with no dependency on Docker/Ollama.

## 11. Validation checklist

### Build validation

- [ ] Build succeeds from a clean output directory.
- [ ] Buildroot package dependencies are declared and reproducible.
- [ ] Package licenses and source versions are recorded.
- [ ] `docs/system-inventory.md` reflects the generated image.
- [ ] RootFS and disk image sizes are measured.
- [ ] Docker Data capacity is checked for supported image modes.

### Boot and runtime validation

- [ ] System boots to the expected console/session.
- [ ] DRM/KMS devices are detected on supported hardware.
- [ ] Keyboard and pointer input work.
- [ ] Niri starts and exits cleanly.
- [ ] Display mode changes and VT switching are tested where supported.
- [ ] Logs are available after a failed session start.
- [ ] Headless mode does not start a compositor.
- [ ] Desktop mode does not require Docker Engine or Docker Data.
- [ ] Docker startup failure does not stop the desktop.
- [ ] Missing GPU acceleration/fallback behavior is documented.
- [ ] Repeated boot and shutdown cycles are tested.

### Integration validation (future shared branch)

- [ ] Ollama can start independently of the desktop.
- [ ] Desktop can start independently of Ollama.
- [ ] Docker GUI access is opt-in and limited to trusted containers.
- [ ] Wayland socket ownership and permissions are correct.
- [ ] Container GUI failure does not terminate Niri.

## 12. Risks and open decisions

| Topic | Status / required evidence |
|---|---|
| Exact Buildroot revision | Confirm from build environment; do not infer from defconfig |
| Niri package availability | Inspect exact Buildroot tree |
| Rust cross-compilation | Prototype and document host/target toolchain requirements |
| Niri/Smithay dependency versions | Verify from selected Niri release |
| Seat/session management | Compare options and test VT/device access |
| GPU support matrix | Define target Intel/AMD/NVIDIA/virtual GPU scope |
| Mesa/EGL acceleration | Test on actual hardware and QEMU separately |
| Firmware | Identify per-driver firmware requirements |
| Login/autologin model | Decide based on RaviOS appliance security/use model |
| Desktop/headless selection | Define persistent configuration mechanism |
| RootFS size | Measure generated footprint and growth margin |
| Docker Data partition impact | Verify all supported disk image modes |
| Desktop recovery behavior | Define compositor crash and restart policy |
| GUI container isolation | Design and test only in later integration phase |

## 13. Development rules and decision log

1. Keep the desktop native to the host RootFS.
2. Keep Docker Engine, Docker Data, and Ollama optional and independent of desktop startup.
3. Keep all RaviOS-specific Buildroot integration in the external tree.
4. Prefer small, testable milestones; do not add a full desktop suite before the compositor proof of concept works.
5. Distinguish build configuration from runtime proof. A package or kernel option in the image is not evidence that the feature works.
6. Record package versions, source hashes, configuration symbols, test hardware, commands, and outcomes.
7. Update this manual in the same change that alters a consequential architecture or operational decision.
8. Do not merge Docker/Ollama changes into this branch during the independent desktop development phase.

### Decision log

| Date | Decision/change | Evidence and notes |
|---|---|---|
| 2026-11-18 | Created the `develop/native-desktop-niri` branch from clean, up-to-date `main`. | Branch creation confirmed in the developer's local Git terminal. |
| 2026-11-18 | Desktop is planned as a native RootFS component and must not depend on Docker Engine, Docker Data, or Ollama. | Branch scope agreed before implementation. |

---

**Current implementation status:** Planning only. No Buildroot packages, kernel options, RootFS files, init scripts, or desktop services have been changed by this manual.
