# Docker Engine Integration

This document describes the Docker Engine integration, Docker Data
storage architecture, management commands, build modes, and validation
completed on RaviOS.

## 1. Overview

RaviOS includes Docker Engine in its Buildroot-based operating system
image. Docker is available immediately after installation without a
separate post-install download or installation step.

Docker persistent data is stored on a dedicated ext4 partition,
separate from the operating system RootFS. The data partition can be
located on the boot disk or an external disk and can be reused across
RaviOS installations and versions.

### Tested environment

- Buildroot: 2026.08.1
- Linux kernel: 7.3.3
- Docker Engine package: 28.5.2
- Architecture: x86_64
- Container runtime: runc
- Storage driver: overlay2
- Cgroup version: 2
- Docker Data filesystem: ext4
- Test environment: VirtualBox

## 2. Buildroot Integration

Docker Engine is provided by Buildroot's `docker-engine` package.

The package brings in dependencies including:

- containerd
- iptables
- libseccomp
- cgroupfs-v2-mount

The Docker daemon is integrated into the RaviOS startup process.

## 3. Kernel Configuration

### 3.1 Initial failure

The first image pull from Docker Hub succeeded, but starting the
container failed with:

    failed to create shim task
    OCI runtime create failed
    error setting cgroup config for procHooks process:
    bpf_prog_query(BPF_CGROUP_DEVICE) failed: function not implemented

This indicated that the kernel did not have the required cgroup BPF
support enabled.

### 3.2 Configuration correction

The following kernel options were added to the RaviOS kernel
configuration:

    CONFIG_CGROUPS=y
    CONFIG_BPF_SYSCALL=y
    CONFIG_CGROUP_BPF=y

Configuration file:

`buildroot-external/board/ravios/x86_64/linux.config`

The kernel was reconfigured through Buildroot:

    make -C /workspace/buildroot \
        O=/workspace/output \
        BR2_EXTERNAL=/workspace/buildroot-external \
        linux-reconfigure

The generated kernel configuration was checked, and all three options
were confirmed enabled.

A new RaviOS image was built and booted in VirtualBox. Container
execution then succeeded.

## 4. TLS Certificate Support

Docker Hub access initially required correcting the CA certificate
bundle.

The Debian CA certificate archive used by the Buildroot package was
manually downloaded from a mirror after the cached archive was found to
be empty.

The downloaded archive was verified with this SHA-256 checksum:

    914416a1e44a25733aff51092fe4e27fdec1c9f6e8d1db0b8364922486153134

The resulting certificate bundle was installed at:

`/etc/ssl/certs/ca-certificates.crt`

Its observed size was approximately 176.5 KiB.

After this correction, TLS communication with Docker Hub worked.

## 5. Docker Data Architecture

Docker's persistent data directory is:

`/var/lib/docker`

RaviOS uses a dedicated ext4 partition for Docker Data. The data
partition is independent of the operating system RootFS.

### 5.1 Filesystem identity

A valid Docker Data filesystem must have all of the following:

- Filesystem type: `ext4`
- Filesystem UUID: `66666666-6666-6666-6666-666666666666`
- Filesystem label: `revayat`

The GPT partition label `docker-data` is used as an additional
discovery identifier, but is not a mandatory filesystem validation
condition.

The filesystem UUID and label identify the Docker Data filesystem.
The partition UUID (`PARTUUID`) and parent disk identifier (`DISK_ID`)
provide stable device identity for selection and mounting.

The partition can be located on the boot disk or an external disk.

### 5.2 Build modes

The build script supports two Docker Data modes.

#### Create mode

Create mode reserves a dedicated Docker Data partition on the
RaviOS boot disk.

Example:

    .\build.ps1 -DockerData Create -DiskSize 16G

The disk size is configurable in whole gigabytes and must be at least
3G. The default is 16G.

The EFI and RootFS partitions are created along with the Docker Data
partition, which uses the remaining configured disk capacity.

#### None mode

None mode creates an image containing only the required EFI and
RootFS partitions. It does not create, format, or reserve space for a
Docker Data partition.

Example:

    .\build.ps1 -DockerData None

The disk image size is calculated automatically from the required
partitions. The `DiskSize` parameter is not used in this mode.

At boot, RaviOS searches for an existing valid Docker Data partition.
If none is found, Docker remains stopped. RootFS is never used as a
fallback Docker storage location.

### 5.3 Build parameters

| Parameter     | Default   | Description                                               |
| ------------- | --------- | --------------------------------------------------------- |
| `-DockerData` | `Create`  | `Create` or `None`                                        |
| `-DiskSize`   | `16G`     | Disk capacity in whole gigabytes; used only with `Create` |
| `-OutputPath` | Automatic | Optional build output path                                |

Examples:

    # Default build: 16 GB disk with Docker Data
    .\build.ps1

    # Minimal image without an internal Docker Data partition
    .\build.ps1 -DockerData None

    # Custom 6 GB image with Docker Data
    .\build.ps1 -DockerData Create -DiskSize 6G

    # Custom 32 GB image with Docker Data
    .\build.ps1 -DockerData Create -DiskSize 32G

## 6. Docker Data Discovery and Selection

At boot, RaviOS discovers Docker Data partitions before starting Docker
Engine.

The discovery process scans the boot disk and external disks for
Docker Data candidates. When selecting automatically, a valid
candidate on the boot disk takes priority over external candidates.

### 6.1 Automatic discovery

The automatic discovery rules are:

1. RaviOS scans the boot disk and external disks for Docker Data
   candidates.
2. If any detected candidate fails filesystem validation, discovery
   stops with status `invalid`, regardless of other valid candidates.
3. If exactly one valid Docker Data candidate exists on the boot disk,
   it is selected. Valid external candidates do not override this
   priority.
4. If multiple valid candidates exist on the boot disk, the status
   becomes `ambiguous`.
5. If no valid boot-disk candidate exists and exactly one valid
   external candidate exists, it is selected.
6. If multiple valid external candidates exist, the status becomes
   `ambiguous`.
7. If no valid candidates exist, the status becomes `not_found`.

Invalid or ambiguous storage is never formatted automatically.
Docker does not start when storage is missing, invalid, or ambiguous.

### 6.2 Explicit selection

A user can explicitly select a Docker Data partition:

    ravios-docker-data list
    ravios-docker-data select /dev/sdb1

The selection is persisted using:

- `DISK_ID`: stable identifier of the parent disk
- `PARTUUID`: stable identifier of the selected partition

This avoids relying on temporary device names such as `/dev/sda1`
or `/dev/sdb1`, which may change between boots.

An explicit selection takes priority over automatic boot-disk
discovery. If the selected disk or partition is unavailable or invalid,
RaviOS does not silently fall back to another candidate.

The `select` command saves the selection. It does not immediately
switch the active Docker Data storage.

## 7. Docker Data Management

The management utility is:

    /usr/sbin/ravios-docker-data

Its configuration and runtime state are stored separately from Docker
Data:

    /etc/ravios/docker-data.conf
    /var/lib/ravios/docker-data/status
    /var/lib/ravios/docker-data/candidates

This allows RaviOS to report storage status even when Docker Data is
unavailable.

### 7.1 Available commands

| Command | Description |
| ------- | ----------- |
| `status` | Display current Docker Data status |
| `list` | List detected Docker Data candidates |
| `select <device>` | Save an explicit storage selection |
| `change` | Interactively switch the active Docker Data partition |
| `clear` | Remove explicit selection and return to automatic discovery |
| `retry` | Run discovery again |

Examples:

    ravios-docker-data status

    ravios-docker-data list

    ravios-docker-data select /dev/sdb1

    ravios-docker-data change

    ravios-docker-data clear

    ravios-docker-data retry

### 7.2 Status values

The management utility reports one of the following states:

| Status | Meaning |
| ------ | ------- |
| `ready` | A valid Docker Data partition is mounted and ready |
| `not_found` | No Docker Data partition was found |
| `ambiguous` | Multiple valid candidates require explicit selection |
| `invalid` | A detected Docker Data candidate failed validation |
| `mount_failed` | The selected partition could not be mounted |

The status includes the selected device, stable disk identifier,
partition UUID, and an optional reason.

### 7.3 Changing the active Docker Data partition

The `change` command provides an interactive operation for switching
between valid internal and external Docker Data partitions.

    ravios-docker-data change

The operation:

1. Lists valid candidates with numbered choices.
2. Prompts the user to select a destination.
3. Validates the destination and its stable identity.
4. Checks whether the selected destination is already active.
5. Stops Docker Engine before changing the mount.
6. Unmounts the current Docker Data partition.
7. Persists the new selection.
8. Mounts the selected partition at `/var/lib/docker`.
9. Starts Docker Engine again.

If the selected destination is already active, the command exits
without making changes.

The operation does not format, erase, or copy Docker Data.

If a switching step fails, Docker remains stopped rather than
starting with an uncertain or incorrect data directory.

The current mount is validated before it is unmounted, and the
destination is validated again before the switch.

## 8. Boot and Docker Startup Behavior

Docker Data discovery is performed by:

    /etc/init.d/S50docker-data

Docker Engine startup is handled by:

    /etc/init.d/S60dockerd

The startup sequence ensures that Docker Data is discovered and
validated before Docker Engine starts.

The Docker startup script independently checks:

- The management status is `ready`.
- The selected block device exists.
- The partition UUID matches the saved identity.
- The parent disk identifier matches the saved identity.
- The filesystem is ext4.
- The filesystem UUID and label match the expected values.
- The selected device is actually mounted at `/var/lib/docker`.

If these checks fail, Docker Engine refuses to start.

The operating system itself can continue booting when Docker Data
is unavailable. This prevents a storage problem from making the
RaviOS system unbootable.

RootFS is never used as a fallback Docker Data directory.

## 9. Validation Results

The following scenarios were tested in VirtualBox.

### 9.1 Build without an internal Docker Data partition

Built an image using:

    .\build.ps1 -DockerData None

Verified that:

- The image contained EFI and RootFS partitions only.
- No internal Docker Data partition was created.
- No Docker Data filesystem was formatted.
- The system booted successfully.
- Docker Data status was `not_found`.
- Docker Engine refused to start without valid Docker Data.

### 9.2 Build with an internal Docker Data partition

Built a 6 GB image using:

    .\build.ps1 -DockerData Create -DiskSize 6G

Verified that:

- The image contained EFI, RootFS, and Docker Data partitions.
- The Docker Data partition used ext4.
- The filesystem UUID and label matched the expected identity.
- Docker Data was mounted at `/var/lib/docker`.
- Docker Engine started successfully.

### 9.3 Container execution

Executed:

    docker run --rm hello-world

The container ran successfully and printed the expected
Hello from Docker message.

### 9.4 Persistence across reboot

Created containers and images on the internal Docker Data partition,
then rebooted RaviOS.

Verified that the existing Docker data remained available after reboot.

The container IDs remained unchanged.

### 9.5 External Docker Data

Attached a separate virtual disk containing a valid Docker Data
partition.

Verified that:

- The external partition was discovered.
- The external disk was identified using its stable disk ID.
- The external partition was mounted at `/var/lib/docker`.
- Docker Engine used the external storage successfully.

### 9.6 Discovery priority

Tested with valid Docker Data partitions on both the boot disk and
an external disk.

Verified that automatic discovery selected the internal boot-disk
partition first.

### 9.7 Explicit selection persistence

Selected the external Docker Data partition using:

    ravios-docker-data select /dev/sdb1

Rebooted RaviOS.

Verified that the explicitly selected external partition was mounted
again using its persisted disk and partition identities.

### 9.8 Switching between internal and external storage

Tested the interactive command:

    ravios-docker-data change

Verified that:

- Selecting the currently active partition made no changes.
- Switching from external to internal storage stopped Docker,
  changed the mount, and restarted Docker successfully.
- Switching from internal to external storage worked as expected.
- Existing containers and images remained available on their
  respective Docker Data partitions.
- Container IDs were preserved when switching back to the
  corresponding data partition.

### 9.9 Final image validation

Built a final RaviOS image with Docker Data enabled:

    .\build.ps1 -DockerData Create -DiskSize 6G

Booted the resulting image in VirtualBox.

Verified that:

- Docker Data was automatically detected.
- The management command reported `ready`.
- The `change` command correctly recognized the active partition.
- Docker Engine started successfully.
- `docker info` reported `/var/lib/docker` as the Docker Root Dir.
- `docker run --rm hello-world` completed successfully.

## 10. Current Status

Docker Engine integration and Docker Data management are implemented
and validated in the VirtualBox development environment.

The current implementation supports:

- Docker Engine built into the RaviOS image.
- Build-time selection of Docker Data partition creation.
- Configurable disk size when creating an internal Docker Data
  partition.
- Automatic discovery of internal and external Docker Data storage.
- Stable storage selection using disk and partition identities.
- Explicit storage selection.
- Interactive switching between valid Docker Data partitions.
- Persistence of Docker containers and images across reboots.
- Protection against starting Docker without valid dedicated storage.
- No automatic formatting of existing or invalid Docker Data
  candidates.
- No fallback to RootFS for Docker persistent data.

Validation has been completed in VirtualBox. Testing on additional
physical hardware remains a separate validation task.
