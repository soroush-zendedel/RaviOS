# System Inventory

## Overview

RaviOS automatically generates a system inventory report as part of the image build workflow.

The report provides a snapshot of the Buildroot configuration, installed target contents, active kernel configuration, Docker-related kernel requirements, and generated disk image layout.

The generated report is stored at `docs/system-inventory.md`. It makes the contents and configuration of a particular RaviOS build easier to inspect, review, and compare.

## Automatic Generation

The inventory generator is invoked by `build.ps1` after a successful image build.

It runs in the existing `ravios-dev` Docker container and reads the actual Buildroot output. It does not require additional Docker mounts or a separate build environment.

The report is generated in both successful build paths:

- After creating and starting a new virtual machine.
- When an existing virtual machine is kept and replacement is declined.

Inventory generation is a supplementary reporting step. If it fails, the image build is not treated as failed. A warning is displayed instead.

The generator writes the new report to a temporary file and replaces the previous report only after successful generation. This prevents an incomplete report from overwriting the last valid one.

## Report Contents

The generated report includes the following information:

### Build Overview

- Build ID.
- Buildroot version.
- Linux kernel version.
- BusyBox version.
- Docker Engine version.
- Docker Data build mode.
- Requested disk image size.

### Installed System Contents

- Installed target packages.
- BusyBox applet symbolic links.
- Standalone executable files.
- Symbolic links that are not BusyBox applets.

### Kernel Configuration

- Active kernel options, grouped by category.
- Docker-related kernel requirements and their configured state.

Options configured as `=y` are built into the kernel. Options configured as `=m` are configured as modules; this does not establish that a module is loaded at runtime.

### Disk Image Configuration

- Generated disk image configuration.
- Partition layout and relevant filesystem settings.
- Docker Data partition settings when applicable.

## Interpreting the Report

The inventory describes the generated Buildroot output and configuration. It should not be interpreted as proof that every listed feature is operational on a running machine.

In particular:

- A package listed as installed is present in the generated target filesystem; this does not prove that its service is running.
- A kernel option configured as a module does not prove that the module is loaded.
- Kernel configuration capabilities do not necessarily indicate that a corresponding feature is active at runtime.
- Docker-related kernel settings describe build configuration, not the result of a complete Docker runtime test.

Runtime validation should be documented separately and supported by actual tests.

The report is a build inventory, not a security audit or a complete runtime diagnostic.

## Manual Generation

The generator can also be invoked directly from the repository root:

```powershell
.\tools\generate-system-inventory.ps1
```

By default, it uses the `ravios-dev` container and writes the report to `docs/system-inventory.md`.

Its parameters are:

| Parameter        | Default             | Description                                     |
| ---------------- | ------------------- | ----------------------------------------------- |
| `Container`      | `ravios-dev`        | Docker container providing the Buildroot output |
| `BuildId`        | `manual`            | Identifier recorded in the report               |
| `DockerDataMode` | `Unknown`           | Build mode: `None`, `Create`, or `Unknown`      |
| `DiskSize`       | `Automatic`         | Requested disk image size                       |
| `OutputPath`     | Default report path | Optional output file path                       |

For example:

```powershell
.\tools\generate-system-inventory.ps1 `
    -BuildId "manual-review" `
    -DockerDataMode Create `
    -DiskSize 5G
```

Manual generation requires the configured Docker build container and its Buildroot output to be available.

## Updating the Report

The report is generated from the current Buildroot output. It should be regenerated after relevant build configuration or package changes.

The latest generated report is maintained at `docs/system-inventory.md`.

A failed generation does not replace the previous valid report.

