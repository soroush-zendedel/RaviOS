# RaviOS Docker Data Storage

## 1. Purpose and Scope

This document describes the architecture, implementation, runtime behavior, and maintenance requirements of the Docker Data storage subsystem in RaviOS.

It is intended for developers and maintainers who need to understand, debug, or extend this subsystem. It is not an introductory guide to Linux storage, filesystems, or Docker.

RaviOS is a minimal Buildroot-based x86_64 operating system designed to host Docker Engine. Docker Engine is integrated into the operating-system image, while its persistent data is stored separately from the RootFS.

The Docker Data subsystem is responsible for:

- Discovering existing Docker Data filesystems during system startup.
- Validating candidate partitions and their filesystem identities.
- Selecting an appropriate storage destination according to deterministic rules.
- Mounting the selected filesystem at `/var/lib/docker`.
- Persisting explicit storage selections independently of Docker Data.
- Preventing Docker Engine from starting when storage is unavailable or cannot be verified.
- Providing administrative operations to inspect, select, and change the Docker Data destination.
- Preserving existing Docker data when changing storage destinations.

The subsystem is deliberately conservative. If it cannot establish that the intended Docker Data filesystem is available and correctly mounted, Docker must remain stopped.

This component is not intended to be a general-purpose disk manager or volume-management framework. It manages one active Docker data root and provides a controlled mechanism for changing its backing filesystem.

## 2. Implementation Components

The implementation is distributed across the following files:

| File | Responsibility |
| --- | --- |
| `build.ps1` | Exposes the Docker Data build mode and disk-size parameters. |
| `buildroot-external/board/ravios/x86_64/post-image.sh` | Selects and configures the appropriate disk-image layout. |
| `buildroot-external/board/ravios/x86_64/genimage-uefi.cfg` | Defines the UEFI image layout with an internal Docker Data partition. |
| `buildroot-external/board/ravios/x86_64/genimage-uefi-no-docker-data.cfg` | Defines the UEFI image layout without a Docker Data partition. |
| `buildroot-external/board/ravios/x86_64/post-build.sh` | Ensures runtime scripts are installed with executable permissions. |
| `buildroot-external/rootfs-overlay/etc/init.d/S50docker-data` | Initiates Docker Data discovery during boot. |
| `buildroot-external/rootfs-overlay/etc/init.d/S60dockerd` | Validates Docker Data readiness before starting Docker Engine. |
| `buildroot-external/rootfs-overlay/usr/sbin/ravios-docker-data` | Implements discovery, validation, mounting, persistent selection, switching, and management commands. |

The implementation follows a separation-of-responsibilities model:

1. Build scripts define the initial disk layout.
2. The early boot script initiates storage discovery.
3. The storage manager owns storage policy and operations.
4. The Docker init script independently enforces the storage readiness requirement.

The storage manager is the primary implementation of Docker Data policy. However, Docker startup must not rely exclusively on its previous execution or its status output. The Docker init script performs its own validation against the live system state.

## 3. Core Architectural Principles

### 3.1 Docker Data Must Remain Separate from RootFS

Docker's data root is:

`/var/lib/docker`

This directory must be backed by a dedicated Docker Data filesystem before Docker Engine starts.

The RootFS must never be used as an implicit fallback storage location.

If the dedicated filesystem is missing, invalid, ambiguous, or cannot be mounted and verified, Docker must remain stopped.

This prevents two important failure scenarios:

- Docker silently writes images, layers, containers, and metadata into the relatively small RootFS.
- Docker starts against a different filesystem than the one containing the intended persistent Docker state.

The existence of `/var/lib/docker` as a directory does not establish storage readiness. Only a verified mount from the intended Docker Data partition is acceptable.

### 3.2 Docker Data Must Be Independent of the OS Installation

Docker Data is designed to survive:

- RaviOS upgrades.
- RaviOS reinstalls.
- Replacement of the operating-system disk.
- Movement between compatible RaviOS installations.
- Use as an external storage device.

The Docker Data filesystem is therefore not tied to a particular RootFS image, kernel version, or installation instance.

The operating system must identify the filesystem using its persistent on-disk identity rather than assuming that it belongs to the currently installed image.

### 3.3 Stable Identity Must Be Used Instead of Device Names

Linux device names such as `/dev/sda3` and `/dev/sdb1` are runtime assignments.

They may change when:

- Another disk is connected.
- Disk enumeration order changes.
- The system boots on different hardware.
- An external storage device is attached or removed.

Consequently, transient device names must not be used as persistent selection identifiers.

Explicit selections use:

- `DISK_ID`: the stable disk identifier exposed through `/dev/disk/by-id/`.
- `PARTUUID`: the persistent partition identifier.

The manager resolves these identifiers to the current device node whenever the selected partition must be accessed.

### 3.4 Fail-Closed Storage Policy

The subsystem follows a fail-closed policy.

Docker must not start unless the intended storage destination has been positively identified and verified.

Examples:

- No candidate found: Docker remains stopped.
- Multiple eligible candidates: Docker remains stopped.
- Invalid filesystem: Docker remains stopped.
- Explicitly selected disk missing: Docker remains stopped.
- Mount failure: Docker remains stopped.
- Unexpected mount source: Docker remains stopped.
- Stale or incomplete status: Docker remains stopped.

The system must never resolve uncertainty by choosing the first available disk or falling back to RootFS.

This is an intentional trade-off: data integrity and predictable behavior take precedence over Docker availability.

### 3.5 Storage Management Must Not Destroy Existing Data

Discovery and management operations must never format or erase a Docker Data filesystem.

The following operations are non-destructive:

- `discover`
- `status`
- `list`
- `select`
- `change`
- `clear`
- `retry`

The `change` operation changes the filesystem mounted at `/var/lib/docker`. It does not migrate, merge, copy, or synchronize Docker data between filesystems.

The operator must understand that the contents of the selected destination become the Docker state visible to the daemon.

Any future provisioning or formatting functionality must be implemented as a separate, explicit operation with its own safety checks and destructive confirmation.

## 4. Build-Time Disk Layout

RaviOS supports two Docker Data image-build modes:

- `Create`: creates an internal Docker Data partition as part of the generated disk image.
- `None`: creates an operating-system image without an internal Docker Data partition.

The selected mode determines the initial disk layout. It does not restrict which compatible Docker Data filesystem can be used at runtime.

### 4.1 Create Mode

Example:

```powershell
.\build.ps1 -DockerData Create -DiskSize 6G
```

In `Create` mode, the generated disk image contains:

1. EFI System Partition.
2. RootFS partition.
3. Docker Data partition.

The Docker Data partition is formatted as ext4 and initialized with the designated filesystem identity.

The image configuration is:

`buildroot-external/board/ravios/x86_64/genimage-uefi.cfg`

The Docker Data partition receives the remaining capacity according to the configured disk size and the space required by the other partitions.

The default build mode is `Create`. The default disk size is 16G, and the minimum supported disk size for this mode is 3G.

The internal Docker Data partition provides an immediately available storage destination for a new installation.

However, the internal partition is not permanently coupled to the operating system. It can be replaced as the active Docker Data destination by selecting another compatible internal or external filesystem.

### 4.2 None Mode

Example:

```code
.\build.ps1 -DockerData None
```

In `None` mode, the generated image contains only:

1. EFI System Partition.
2. RootFS partition.

No Docker Data partition is created, formatted, or reserved.

The image configuration is:

`buildroot-external/board/ravios/x86_64/genimage-uefi-no-docker-data.cfg`

The image size is calculated from the required partitions. The `-DiskSize` parameter is not used in this mode.

At runtime, RaviOS still searches for an existing compatible Docker Data filesystem.

The search order is:

1. Docker Data candidates on the boot disk.
2. Docker Data candidates on external disks.

If no valid candidate is found, the operating system boots normally, but Docker remains unavailable.

This mode is intended for installations where Docker state is stored on a separate disk or where the operating-system image should not reserve space for Docker data.

### 4.3 Build-Time and Runtime Independence

The build mode must not be treated as a runtime storage-selection rule.

For example:

- An image built with `Create` can use an external Docker Data filesystem instead of its internal partition.
- An image built with `None` can use an existing Docker Data filesystem connected during boot.
- A missing internal partition does not imply that the system should initialize or format another disk.
- The runtime manager must inspect actual devices and filesystem identities rather than relying on the image build configuration.

The build process provisions an initial layout. Runtime discovery determines which existing filesystem is eligible for use.

## 5. Docker Data Filesystem Identity

Docker Data uses a designated ext4 filesystem identity.

| Property                     | Required value                         |
| ---------------------------- | -------------------------------------- |
| Filesystem type              | `ext4`                                 |
| Filesystem UUID              | `66666666-6666-6666-6666-666666666666` |
| Filesystem label             | `revayat`                              |
| Conventional partition label | `docker-data`                          |

These identifiers serve different purposes and must not be confused.

### 5.1 Filesystem UUID

The filesystem UUID identifies the ext4 filesystem itself.

It is used to recognize the designated Docker Data filesystem independently of its current device name.

The UUID is part of the persistent storage compatibility contract.

### 5.2 Filesystem Label

The filesystem label is `revayat`.

It provides an additional filesystem-level identity check.

A candidate must have the expected filesystem type, UUID, and filesystem label before it can be accepted.

### 5.3 Partition Label

The GPT partition label `docker-data` is a discovery identifier.

It helps the manager identify partitions that are intended to contain Docker Data.

However, the partition label is not a mandatory filesystem validation condition.

The distinction is important:

- Filesystem UUID and filesystem label are required identity checks.
- Partition label is an additional discovery hint.

Do not change these identifiers without considering existing Docker Data filesystems.

Changing the UUID or filesystem label is an on-disk compatibility change. It may make previously created Docker Data partitions undiscoverable unless a migration or compatibility mechanism is implemented.

## 6. Stable Disk and Partition Identity

Persistent selection uses two identifiers.

### 6.1 DISK_ID

`DISK_ID` identifies the physical or virtual disk using a stable identifier exposed through `/dev/disk/by-id/`.

It identifies the parent disk rather than a transient partition device name.

The manager must resolve the selected partition's parent disk and determine its stable disk identifier.

### 6.2 PARTUUID

`PARTUUID` identifies the selected partition independently of its Linux device name.

It is used to locate the intended partition after device enumeration changes.

### 6.3 Why Both Identifiers Are Required

Using only `PARTUUID` identifies a partition, but does not explicitly preserve the identity of its parent disk.

Using only `DISK_ID` identifies a disk, but does not uniquely identify which partition on that disk is intended.

Together, they identify the selected storage destination.

A persistent selection therefore consists of:

```code
DISK_ID=<stable disk identifier>
PARTUUID=<partition identifier>
```

At runtime, the manager resolves the selected disk and partition from these values.

The resolved device node, such as `/dev/sda3`, is temporary runtime information and must not replace the persistent identifiers.

If either the selected disk or partition cannot be resolved, the selection is considered unavailable. The manager must not silently select another candidate.

## 7. Boot Sequence and Service Ordering

Docker Data discovery must complete before Docker Engine is allowed to start.

The relevant startup sequence is:

1. The kernel discovers block devices and partitions.
2. The device-management layer exposes block-device nodes and persistent disk identifiers.
3. The `S50docker-data` init script invokes the storage manager.
4. The manager evaluates an explicit selection, if one exists.
5. If no explicit selection exists, the manager applies automatic discovery policy.
6. A valid and unambiguous candidate is mounted at `/var/lib/docker`.
7. The manager records the resulting runtime status.
8. The `S60dockerd` init script independently validates the recorded status and the live mount.
9. Docker Engine starts only if all storage checks succeed.

### 7.1 S50docker-data

The early boot script delegates storage policy to the management utility:

```code
/usr/sbin/ravios-docker-data discover
```

The init script does not implement candidate selection or filesystem validation itself.

This keeps the storage policy centralized in `ravios-docker-data`.

The script is intentionally non-fatal to the operating-system boot process.

If Docker Data is unavailable, the script reports the condition but allows the operating system to continue booting.

This is necessary because a missing Docker Data disk should not make the appliance itself unbootable.

### 7.2 S60dockerd

The Docker init script is responsible for enforcing the final storage readiness condition.

It does not assume that successful execution of `S50docker-data` proves that storage is still valid.

Before starting Docker, it independently checks the runtime status, device identity, filesystem identity, and actual mount source.

If any required condition fails, Docker must not start.

This independent validation is essential because the system state may change after discovery.

Examples include:

- A disk being disconnected.
- A device node being reassigned.
- A mount being replaced.
- A stale status file remaining after an interrupted operation.
- A filesystem being mounted from an unexpected partition.

### 7.3 Operating-System Availability

The storage subsystem must not make Docker availability a prerequisite for the operating system itself.

The intended behavior is:

- RaviOS boots even when no Docker Data filesystem is present.
- SSH and other base-system administration facilities remain available.
- Docker stays stopped until valid storage is available.
- The operator can attach or restore storage and retry discovery.

This separation allows RaviOS to remain manageable during storage failures.

## 8. Docker Data Discovery

The discovery subsystem identifies existing Docker Data partitions and determines whether one of them can safely become the active Docker storage destination.

Discovery consists of several distinct operations:

1. Enumerating available block-device partitions.
2. Identifying potential Docker Data candidates.
3. Validating candidate filesystem properties.
4. Determining whether each candidate belongs to the boot disk or an external disk.
5. Applying the automatic selection policy or resolving an explicit selection.
6. Mounting the selected candidate.
7. Publishing the resulting runtime status.

Candidate discovery and candidate activation are separate concepts.

A partition being detected does not mean it is valid, selected, mounted, or ready for Docker.

## 9. Candidate Identification and Validation

### 9.1 Candidate Identification

The manager examines available block-device partitions and identifies potential Docker Data candidates through either the designated filesystem UUID or the conventional partition label.

The relevant identifiers are:

- Filesystem UUID: `66666666-6666-6666-6666-666666666666`
- Filesystem label: `revayat`
- Partition label: `docker-data`

The partition label is an additional discovery identifier, not a mandatory filesystem validation condition.

The discovery process must not assume that every partition carrying the conventional partition label is a valid Docker Data filesystem.

Likewise, a partition may be identifiable through its filesystem UUID even if its GPT partition label is different or absent.

### 9.2 Candidate Validation

A candidate must be validated before it can be mounted.

The required filesystem properties are:

- The device must be a block-device partition.
- The filesystem type must be `ext4`.
- The filesystem UUID must match the designated Docker Data UUID.
- The filesystem label must be `revayat`.
- The partition must have a resolvable PARTUUID.
- The parent disk must have a resolvable stable disk identifier.

The manager must distinguish between:

- A detected candidate.
- A valid candidate.
- An invalid candidate.
- A selected candidate.
- A mounted candidate.
- A ready Docker Data destination.

These states must not be treated as interchangeable.

### 9.3 Invalid Candidates

An invalid candidate must not be silently accepted or mounted.

Examples include:

- A partition with the expected partition label but an incorrect filesystem UUID.
- A partition with the expected UUID but an unexpected filesystem type.
- A filesystem with an incorrect label.
- A partition whose parent disk identity cannot be established.
- A partition whose PARTUUID cannot be resolved.

Any detected candidate that fails the required validation checks must prevent automatic selection. The manager must report the invalid candidate and its validation failure rather than silently ignoring it.

This rule applies even when another valid candidate exists on the boot disk. Automatic selection must not proceed while any detected invalid candidate remains unresolved.

The manager should report the reason for rejection so that the operator can diagnose the problem.

## 10. Boot Disk and External Disk Classification

Automatic discovery distinguishes between partitions on the boot disk and partitions on external disks.

The boot disk is determined from the device containing the running system's root filesystem.

The manager must resolve the root filesystem partition to its parent disk before comparing it with candidate partitions.

This distinction is important because the boot partition itself is not necessarily the physical disk identifier.

For example:

```text
/dev/sda
├── /dev/sda1   EFI
├── /dev/sda2   RootFS
└── /dev/sda3   Docker Data
```

In this example, `/dev/sda3` belongs to the boot disk because its parent disk is `/dev/sda`.

An external disk may appear as:

```code
/dev/sdb
└── /dev/sdb1   Docker Data
```

The manager must classify candidates based on their parent disk identity, not by assumptions about `sda`, `sdb`, or any other device-name ordering.

## 11. Automatic Discovery and Selection Policy

Automatic discovery follows a deterministic priority policy.

The boot disk has priority over external disks.

The selection rules are:

### 11.1 Exactly One Valid Boot-Disk Candidate

If exactly one valid Docker Data candidate exists on the boot disk, it is selected.

External candidates do not override this decision.

For example:

```code
Boot disk:
  /dev/sda3  valid Docker Data

External disks:
  /dev/sdb1  valid Docker Data
```

The manager selects the internal candidate on `/dev/sda3`.

### 11.2 Multiple Boot-Disk Candidates

If multiple valid Docker Data candidates exist on the boot disk, the result is ambiguous.

The manager must not select one based on device order, partition number, or enumeration order.

Docker remains unavailable until the ambiguity is resolved.

### 11.3 No Valid Boot-Disk Candidate and Exactly One Valid External Candidate

If no valid candidate exists on the boot disk and exactly one valid external candidate exists, the external candidate is selected.

Example:

```code
Boot disk:
  No valid Docker Data candidate

External disks:
  /dev/sdb1  valid Docker Data
```

The manager selects `/dev/sdb1`.

### 11.4 Multiple Valid External Candidates

If no valid boot-disk candidate exists and multiple valid external candidates are available, automatic selection is ambiguous.

The manager must not choose the first external disk or use device enumeration order as a tie-breaker.

An explicit operator selection is required.

### 11.5 No Candidate Found

If no Docker Data candidate is found, the manager reports that storage is unavailable.

The operating system continues booting, but Docker remains stopped.

The manager must not:

- Use RootFS as a fallback.
- Format an arbitrary partition.
- Create a new Docker Data filesystem automatically.
- Select an unrelated disk.

### 11.6 Invalid Candidate Handling

Invalid candidates must not be treated as valid storage destinations.

If any detected candidate fails the required validation checks, automatic selection must be rejected. The manager must report the invalid candidate and its validation failure rather than silently ignoring it.

## 12. Explicit Storage Selection

Automatic discovery is not always sufficient.

An operator may have multiple Docker Data filesystems, or may intentionally prefer an external disk over the internal one.

For these situations, RaviOS supports persistent explicit selection.

An explicit selection is stored using:

- `DISK_ID`
- `PARTUUID`

The selection is independent of the current Linux device name.

### 12.1 Explicit Selection Takes Priority

When an explicit selection exists, the manager resolves that selection instead of applying automatic candidate selection.

The explicit selection is authoritative.

The manager must verify that:

1. The selected disk can be resolved using its stable identifier.
2. The selected partition can be found using its PARTUUID.
3. The partition belongs to the selected disk.
4. The filesystem type, UUID, and label are correct.
5. The candidate can be mounted and verified.

Only after all required checks succeed may the selected filesystem become ready.

### 12.2 No Automatic Fallback

An unavailable explicit selection must not trigger automatic discovery as a fallback.

For example:

```code
Persisted selection:
  DISK_ID=ata-EXTERNAL_DISK
  PARTUUID=1111-2222

Current devices:
  Internal Docker Data: /dev/sda3
  Selected external disk: Missing
```

Even though a valid internal Docker Data partition exists, RaviOS must not automatically switch to it.

The selected external disk may be temporarily disconnected. Automatically switching to another Docker Data filesystem could expose a different and potentially outdated Docker state.

The correct behavior is:

- Report the selected destination as unavailable.
- Keep Docker stopped.
- Preserve the explicit selection.
- Wait for the selected disk to return or for the operator to change the selection.

### 12.3 Returning to Automatic Discovery

To return to automatic discovery, the operator must explicitly clear the saved selection.

After the selection is cleared, the normal automatic discovery policy applies again.

This makes the difference between automatic and explicit storage selection predictable and persistent across reboots.

## 13. Discovery Decision Table

The following table summarizes the expected automatic behavior:

| Boot-Disk Candidates              | External Candidates | Result                                |
| --------------------------------- | ------------------- | ------------------------------------- |
| Exactly one valid                 | None                | Select boot-disk candidate            |
| Exactly one valid                 | One or more valid   | Select boot-disk candidate            |
| Multiple valid                    | Any                 | Ambiguous; do not mount automatically |
| None                              | Exactly one valid   | Select external candidate             |
| None                              | Multiple valid      | Ambiguous; do not mount automatically |
| None                              | None                | Storage unavailable                   |
| Any detected invalid candidate    | Any                 | Reject unsafe automatic selection     |

An existing explicit selection overrides this automatic decision table.

If the explicit destination cannot be resolved or validated, the manager must report failure without falling back to automatic discovery.

## 14. Persistent State Management

The Docker Data subsystem maintains two logically separate types of state:

1. Persistent storage selection.
2. Runtime storage status.

These states serve different purposes and must not be confused.

### 14.1 Persistent Selection

Persistent selection records the storage destination explicitly chosen by the operator.

It uses:

- `DISK_ID`
- `PARTUUID`

These values identify the selected disk and partition independently of Linux device enumeration.

The selection configuration must be stored outside `/var/lib/docker`.

This is essential because the system must know which filesystem to mount before it can access the contents of that filesystem.

Storing the selection only inside Docker Data would create a circular dependency:

1. The system needs to know which filesystem to mount.
2. The selection information would only be available after mounting that filesystem.
3. Therefore, the system could not reliably resolve the initial mount.

Persistent selection must survive reboot and must remain available even when the selected Docker Data disk is disconnected.

### 14.2 Runtime Status

Runtime status records the result of the most recent discovery and activation attempt.

It describes whether Docker Data is currently ready and identifies the resolved device and storage identity.

The status is used by `S60dockerd` as an input to its independent validation process.

A ready status must contain sufficient information to identify the active storage destination, including:

- `STATUS=ready`
- `DEVICE`
- `DISK_ID`
- `PARTUUID`

Additional diagnostic information may be stored to explain why discovery or mounting failed.

Runtime status is not a persistent selection.

For example, a filesystem may be automatically selected during one boot without creating an explicit selection configuration.

Similarly, an explicit selection may remain saved while its disk is disconnected and the runtime status reports that storage is unavailable.

### 14.3 Atomic State Updates

State files must not be left partially written if the system is interrupted during an update.

The manager should write a complete replacement state to a temporary file and then atomically replace the previous state.

The implementation must avoid exposing an incomplete state as a valid ready state.

In particular:

- Do not publish `STATUS=ready` before successful mounting and verification.
- Clear or replace stale ready status when a new discovery attempt begins.
- On failure, publish an unavailable or error state.
- Preserve the explicit selection when the selected disk is temporarily unavailable.
- Do not allow a failed selection change to leave Docker running against an uncertain destination.

The selection configuration and runtime status must remain separate because they represent different facts.

## 15. Mount Lifecycle

The Docker Data filesystem is mounted at:

`/var/lib/docker`

The mount lifecycle is owned by `ravios-docker-data`.

The manager must validate the candidate before mounting it and verify the resulting mount after the mount operation succeeds.

### 15.1 Before Mounting

Before attempting to mount a candidate, the manager must verify:

1. The candidate is a block-device partition.
2. Its filesystem type is `ext4`.
3. Its filesystem UUID matches the designated UUID.
4. Its filesystem label is `revayat`.
5. Its PARTUUID can be resolved.
6. Its parent disk has a stable disk identifier.
7. The destination mount point is available and not occupied by an unexpected mount.

A candidate that fails any required check must not be mounted.

### 15.2 Mount Operation

After validation, the manager mounts the selected filesystem at:

`/var/lib/docker`

The mount must be performed using the resolved device node for the validated partition.

The manager must not assume that the mount succeeded merely because the `mount` command returned success.

The resulting mount must be inspected to confirm that:

- `/var/lib/docker` is actually mounted.
- The mount source corresponds to the intended partition.
- The filesystem type is `ext4`.

### 15.3 Ready-State Publication

Only after successful mount verification may the manager publish:

`STATUS=ready`

The recorded device and stable identifiers must describe the filesystem that is actually mounted.

If mounting or verification fails:

- The manager must not publish a ready state.
- The runtime status must indicate failure or unavailability.
- Docker must remain stopped.

### 15.4 Mountpoint Safety

The manager must distinguish between:

- An existing directory at `/var/lib/docker`.
- A mounted filesystem at `/var/lib/docker`.
- The expected Docker Data filesystem mounted at `/var/lib/docker`.

These are three different conditions.

An existing directory is not sufficient.

A mounted filesystem is not sufficient unless it is the intended Docker Data filesystem.

The manager must reject an unexpected mount rather than unmounting or replacing it without validating its identity.

## 16. Docker Startup Gate

`S60dockerd` is the final safety boundary between storage discovery and Docker Engine startup.

Its responsibility is not to discover alternative storage destinations. Its responsibility is to prove that the active Docker Data mount is valid before allowing the daemon to start.

The startup gate independently checks the runtime status and the live system.

### 16.1 Required Status

The status file must be readable and indicate:

`STATUS=ready`

The required identity fields must also be present:

- `DEVICE`
- `DISK_ID`
- `PARTUUID`

An incomplete status file must be rejected.

### 16.2 Device Validation

The recorded device must resolve to a block-device partition.

The manager must not assume that a previously recorded `/dev/sdX` path still refers to the same physical partition.

The startup gate verifies the current partition identity using PARTUUID.

### 16.3 Parent Disk Validation

The partition must belong to the disk identified by the recorded `DISK_ID`.

This prevents a device-name change or unexpected partition mapping from causing Docker to use another disk.

### 16.4 Filesystem Validation

The candidate filesystem must satisfy all required properties:

- Filesystem type: `ext4`
- Filesystem UUID: `66666666-6666-6666-6666-666666666666`
- Filesystem label: `revayat`

The partition label is not a mandatory startup validation condition.

### 16.5 Live Mount Validation

The startup gate must verify that `/var/lib/docker` is actually mounted.

It must also confirm that the mount source corresponds to the expected device and that the mounted filesystem type is correct.

A ready status file alone is never sufficient.

The checks must establish that the intended filesystem is mounted at the exact Docker data-root path.

### 16.6 Start and Reload Behavior

Docker may start or reload only after all storage checks succeed.

If a check fails, the init script must refuse the operation and report the reason.

The stop operation must remain independent of storage readiness.

This is important because Docker may need to be stopped during recovery or storage switching, including situations where the storage status is already invalid.

Do not weaken this startup gate to a simple directory-existence check or a generic mountpoint check.

The purpose of the gate is to verify storage identity, not merely storage availability.

## 17. Failure-State Handling

The storage manager and Docker init script must cooperate to preserve a consistent failure state.

Examples:

| Failure | Required behavior |
| --- | --- |
| Status file missing | Docker must not start |
| Status file incomplete | Docker must not start |
| Status is not `ready` | Docker must not start |
| Recorded device missing | Docker must not start |
| PARTUUID mismatch | Docker must not start |
| DISK_ID mismatch | Docker must not start |
| Wrong filesystem type | Docker must not start |
| Wrong filesystem UUID | Docker must not start |
| Wrong filesystem label | Docker must not start |
| Mountpoint not mounted | Docker must not start |
| Mount source differs from recorded device | Docker must not start |
| Mount verification fails | Docker must not start |

Failure reporting should preserve useful diagnostic information.

The system should distinguish between an unavailable disk, an invalid candidate, an ambiguous discovery result, and a mount failure whenever possible.

The operating system itself must remain available for administration.

## 18. Why Discovery and Startup Validation Are Separate

The separation between `ravios-docker-data` and `S60dockerd` is intentional.

Discovery happens during the boot sequence and may also happen later through management commands.

Docker startup happens when the service is started or restarted.

These events are not guaranteed to occur under an unchanged hardware or mount state.

For example:

1. Discovery finds a valid external disk.
2. The manager mounts it and publishes ready status.
3. The disk is disconnected or the mount is replaced.
4. Docker is started later.

If Docker trusted only the earlier discovery result, it could start against an incorrect or missing data root.

The independent startup gate closes this gap by validating the current state immediately before allowing Docker to run.

The two components therefore have complementary responsibilities:

- `ravios-docker-data` establishes and manages the intended storage state.
- `S60dockerd` verifies that the state is still valid before starting Docker.

## 19. Management Interface

The Docker Data management utility is:

`/usr/sbin/ravios-docker-data`

It provides the administrative interface for inspecting and managing Docker Data storage.

The utility centralizes storage operations so that boot scripts and administrators use the same implementation and validation rules.

The supported commands are:

| Command | Purpose |
| --- | --- |
| `status` | Display current Docker Data runtime status and selected storage information. |
| `list` | Enumerate detected Docker Data candidates and report their validation status. |
| `select <device>` | Persist an explicit storage selection using stable disk and partition identifiers. |
| `change` | Interactively select and switch to another valid Docker Data destination. |
| `clear` | Remove the explicit selection and return to automatic discovery. |
| `retry` | Retry storage discovery after a previous failure or device change. |
| `discover` | Execute the discovery operation used during system boot. |

The management utility must be the authoritative interface for storage policy.

Other scripts should invoke its commands instead of independently implementing discovery or selection logic.

### 19.1 Status

Usage:

```sh
ravios-docker-data status
```

Displays the current runtime state.

The output should help an administrator determine:

- Whether Docker Data is ready.
- Which device is currently active.
- Which stable disk identity is associated with it.
- Which partition identity is associated with it.
- Whether an explicit selection exists.
- Why storage is unavailable, if applicable.

The reported runtime device must not be interpreted as the persistent identity of the selected storage.

### 19.2 List

Usage:

```code
ravios-docker-data list
```

Lists detected candidates and their validation status.

The output is intended to help an administrator distinguish valid destinations from invalid or unavailable candidates before making a selection.

Candidate enumeration must not modify filesystems or mount arbitrary partitions.

The command is informational and must not change the active Docker Data destination.

### 19.3 Select

Usage:

```code
ravios-docker-data select /dev/sdb1
```

Persists an explicit selection for the specified partition.

The command validates the requested device and resolves its stable identity.

The saved selection consists of:

- `DISK_ID`
- `PARTUUID`

The command does not use the transient device path as the persistent selection identifier.

`select` is a configuration operation. It does not perform the complete interactive storage-switch workflow.

The selected destination is resolved and activated by a subsequent discovery or retry operation, or during the next boot.

The command must reject invalid partitions and must not format or modify the selected filesystem.

### 19.4 Change

Usage:

```code
ravios-docker-data change
```

`change` is the interactive operation for switching the active Docker Data destination.

It presents available valid candidates and asks the operator to choose one.

The operation is designed to change the mounted Docker data root without formatting, copying, merging, or deleting data.

Its safety requirements are described in Section 20.

### 19.5 Clear

Usage:

```code
ravios-docker-data clear
```

Removes the persisted explicit selection.

After the selection is cleared, the manager returns to automatic discovery policy.

The command does not format, erase, or delete any Docker Data filesystem.

After removing the explicit selection, the manager runs automatic discovery to determine whether a valid Docker Data destination can be activated.

If automatic discovery fails or returns an ambiguous result, Docker remains stopped and the runtime status reports the failure.

Docker must never be allowed to continue using an unverified destination during the transition.

### 19.6 Retry

Usage:

```code
ravios-docker-data retry
```

Retries discovery after a storage-related failure.

Typical use cases include:

- Connecting an external disk after the operating system has booted.
- Restoring a previously disconnected selected disk.
- Resolving a mount failure.
- Retrying after an operator has corrected a filesystem or device issue.

If an explicit selection exists, retry must continue to honor it.

Retry must not silently switch to automatic discovery when the explicitly selected destination is unavailable.

### 19.7 Discover

Usage:

```code
ravios-docker-data discover
```

Executes the discovery operation used during boot.

It applies the existing selection policy, validates the chosen destination, and attempts to mount it.

It is not a provisioning operation.

It must never format or initialize a candidate filesystem.

## 20. Storage Switching Lifecycle

The `change` operation is the most sensitive management operation because it changes the filesystem backing `/var/lib/docker`.

The operation must be treated as a controlled storage transition, not as a simple mount command.

### 20.1 Candidate Enumeration

The manager discovers available Docker Data candidates and presents valid destinations to the operator.

Invalid candidates must not be offered as selectable destinations.

The candidate information must be based on actual device and filesystem validation.

### 20.2 Destination Selection

The operator selects the desired destination.

The selected candidate must be validated again before any destructive-to-runtime action, such as stopping Docker or unmounting the current filesystem.

The manager must not rely exclusively on candidate information gathered before the operator made the selection.

The destination may have disappeared or changed between enumeration and selection.

### 20.3 No-Op for the Current Destination

If the requested destination is already mounted at `/var/lib/docker` and its complete identity matches the active destination, the operation should exit without changing anything.

This avoids unnecessary:

- Docker shutdown.
- Filesystem unmounting.
- Filesystem remounting.
- Docker restart.
- Changes to persistent selection.

A matching device path alone is not sufficient to establish that the current destination is the same storage target. The stable identity and live mount must also agree.

### 20.4 Validate the Current Mount

Before unmounting the current Docker Data filesystem, the manager must verify that the mount at `/var/lib/docker` is the expected managed mount.

It must not blindly unmount an unrelated filesystem.

If the current mount cannot be identified safely, the operation must stop and report the problem.

### 20.5 Stop Docker

Docker must be stopped before its data filesystem is unmounted. If Docker cannot be stopped successfully, the manager must not proceed with unmounting.

Unmounting a filesystem while Docker is actively using it risks filesystem errors and inconsistent Docker state.

### 20.6 Unmount the Current Destination

After Docker has stopped and the current mount has been validated, the manager can unmount `/var/lib/docker`.

If unmounting fails, it must not proceed as though the old filesystem has been detached successfully.

The manager must report the failure and leave Docker stopped.

### 20.7 Mount the New Destination

The selected destination is mounted at `/var/lib/docker`.

The manager must verify the resulting mount source and filesystem identity.

A successful mount command alone is not sufficient.

The mounted filesystem must correspond to the destination selected by the operator.

### 20.8 Persist the New Selection

After the new destination has been mounted and verified, the manager persists its stable identity:

- `DISK_ID`
- `PARTUUID`

The runtime status must describe the actual mounted filesystem.

The manager must not publish a ready state for an unverified destination.

### 20.9 Restart Docker

Docker may be restarted only after the new storage state is valid.

The `S60dockerd` startup gate performs its own independent checks before starting the daemon.

This ensures that switching and Docker startup share the same storage safety requirements.

### 20.10 Failure Handling

If any switching step fails, the manager must not start Docker against an uncertain destination.

Examples:

| Failure point                             | Required behavior                                                   |
| ----------------------------------------- | ------------------------------------------------------------------- |
| Destination validation fails              | Do not stop or unmount the current destination.                     |
| Current mount identity cannot be verified | Abort the operation.                                                |
| Docker cannot be stopped                  | Do not unmount the current filesystem.                              |
| Unmount fails                             | Do not mount another destination over the existing mount.           |
| New mount fails                           | Do not publish ready status.                                        |
| New mount verification fails              | Do not start Docker.                                                |
| Selection persistence fails               | Do not start Docker with an uncertain selection state.              |
| Docker restart fails                      | Report the failure; do not claim the switch completed successfully. |

The newly mounted filesystem may remain mounted, but Docker must remain stopped.

If the operation fails before the new selection is persisted, the previous persistent selection must remain unchanged.

If the new selection has already been persisted but Docker restart fails, the new selection remains saved. The operation must still be reported as unsuccessful, and Docker must remain stopped until storage and service readiness are verified.

A failed operation must leave the system in a state where Docker cannot access an unverified Docker data root.

The manager must not automatically fall back to another disk after a failed explicit switch.

## 21. Error Handling and Recovery

The subsystem distinguishes between storage discovery, validation, activation, and service-start failures.

These failures should remain diagnosable.

Typical failure categories include:

| Category              | Description                                                        |
| --------------------- | ------------------------------------------------------------------ |
| `not_found`           | No eligible Docker Data filesystem was found.                      |
| `invalid`             | A detected candidate failed required validation.                   |
| `ambiguous`           | Multiple candidates prevent deterministic automatic selection.     |
| `unavailable`         | An explicitly selected destination cannot currently be resolved.   |
| `mount_failed`        | The selected filesystem could not be mounted.                      |
| `verification_failed` | The resulting mount or device identity did not match expectations. |
| `selection_failed`    | Persistent selection could not be updated safely.                  |

These names describe conceptual failure categories. The exact status strings and reason values are implementation details and must be checked in the current management script before being used by external automation.

### 21.1 Recovery After a Missing Disk

If an explicitly selected disk is disconnected:

1. Docker remains stopped.
2. The explicit selection remains saved.
3. The manager reports that the selected destination is unavailable.
4. The operator reconnects the disk.
5. The operator runs `retry`.
6. The manager resolves the same stable disk and partition identities.
7. Docker starts only after the destination is mounted and verified.

The manager must not choose another available Docker Data filesystem during this recovery.

### 21.2 Recovery After Ambiguous Discovery

If multiple candidates make automatic selection ambiguous:

1. Inspect the candidates using `list`.
2. Determine which filesystem should be active.
3. Use `select` or `change` to make an explicit choice.
4. Verify the active state using `status`.
5. Confirm that the expected filesystem is mounted at `/var/lib/docker`.

The system should not resolve ambiguity by relying on disk order.

### 21.3 Recovery After a Mount Failure

If mounting fails:

1. Inspect the manager's status and diagnostic reason.
2. Check the device and filesystem using system storage tools.
3. Correct the underlying problem.
4. Run `retry`.
5. Verify the mount and runtime status.
6. Confirm Docker starts only after successful validation.

Do not manually create a ready status file to bypass the startup gate.

## 22. Development and Maintenance Rules

Changes to the Docker Data subsystem must preserve its storage safety contract.

### 22.1 Never Persist `/dev/sdX` as Selection Identity

Device paths are runtime values.

Persist only stable identifiers such as `DISK_ID` and `PARTUUID`.

A device path may be recorded in runtime status for diagnostics and current mount verification, but it must not replace the persistent identity.

### 22.2 Keep Candidate Discovery Separate from Candidate Activation

Candidate enumeration must not automatically mount every matching partition.

The implementation should preserve distinct stages:

1. Detection.
2. Validation.
3. Classification.
4. Selection.
5. Mounting.
6. Mount verification.
7. Ready-state publication.

This separation makes the selection policy testable and prevents accidental activation of ambiguous storage.

### 22.3 Keep the Startup Gate Independent

Do not remove or bypass the independent validation in `S60dockerd`.

A successful discovery operation does not guarantee that the hardware and mount state remain unchanged until Docker starts.

### 22.4 Never Format During Discovery or Switching

Do not add filesystem creation or formatting to:

- `discover`
- `retry`
- `select`
- `change`
- `clear`

These commands must remain non-destructive.

First-time provisioning, if introduced in the future, must be a separate explicit workflow.

### 22.5 Keep Runtime State Outside Docker Data

Selection and runtime status must remain accessible when Docker Data is missing or disconnected.

Do not move the manager's required state into `/var/lib/docker`.

### 22.6 Preserve Safe Failure Behavior

Every new operation must define its failure behavior.

A failure must not accidentally:

- Start Docker.
- Publish ready status.
- Mount an unverified candidate.
- Unmount an unrelated filesystem.
- Replace an explicit selection with an automatic fallback.
- Format or erase existing Docker data.

When uncertain, the operation must abort and leave Docker stopped.

### 22.7 Keep Storage Policy Centralized

Do not duplicate candidate selection or filesystem identity rules across init scripts.

`ravios-docker-data` owns discovery and management policy.

`S50docker-data` invokes the manager during boot.

`S60dockerd` independently verifies the result before Docker starts.

This separation should remain intact as the subsystem evolves.

## 23. Testing Strategy

Any modification to the Docker Data subsystem must be validated against both build-time image layouts and runtime storage behavior.

A successful build alone is not sufficient.

Testing must establish that:

- Both image layouts are generated correctly.
- Discovery follows the documented selection policy.
- Persistent selections survive reboot.
- Storage switching does not corrupt or discard existing data.
- Docker never starts without the intended filesystem mounted.
- Failure conditions leave Docker stopped.
- The base operating system remains bootable when Docker Data is unavailable.

Virtual machine testing is the minimum validation requirement before considering a storage-related change complete.

Physical hardware testing should follow when the change affects device discovery, disk identification, partition enumeration, or external storage compatibility.

## 24. Build-Time Validation

### 24.1 Create Mode

Build an image with an internal Docker Data partition:

```powershell
.\build.ps1 -DockerData Create -DiskSize 6G
```

Verify the generated image contains:

1. EFI System Partition.
2. RootFS partition.
3. Docker Data partition.

Inspect the partition table and confirm:

- The partition layout is correct.
- The Docker Data partition has the expected partition type and layout.
- The filesystem is ext4.
- The filesystem UUID is correct.
- The filesystem label is `revayat`.

The generated image size must correspond to the requested disk capacity and the configured partition layout.

### 24.2 None Mode

Build an image without an internal Docker Data partition:

```code
.\build.ps1 -DockerData None
```

Verify the generated image contains only:

1. EFI System Partition.
2. RootFS partition.

Confirm that:

- No Docker Data partition is created.
- No Docker Data filesystem is formatted.
- No extra capacity is reserved for Docker Data.
- The image size is calculated from the required partitions.
- The build does not require a disk-size parameter in this mode.

### 24.3 Build Script Validation

Verify that the build script:

- Accepts only supported Docker Data modes.
- Applies disk-size validation only when required.
- Uses the correct Genimage configuration for each mode.
- Does not pass an unused disk-size value to the `None` image layout.
- Reports the selected build mode clearly.

## 25. Runtime Boot and Discovery Tests

### 25.1 Internal Docker Data

Boot an image built with `Create` mode.

Verify:

```code
ravios-docker-data status
```

Expected behavior:

- The internal Docker Data partition is detected.
- The internal candidate is selected.
- The filesystem is mounted at `/var/lib/docker`.
- Runtime status reports `ready`.
- Docker starts successfully.

Inspect the actual mount:

```code
findmnt /var/lib/docker
```

Confirm that the mount source is the expected internal partition.

### 25.2 No Docker Data Available

Boot an image built with `None` mode without connecting an external Docker Data disk.

Expected behavior:

- RaviOS boots normally.
- The storage manager reports that Docker Data is unavailable.
- `/var/lib/docker` is not treated as persistent Docker storage.
- Docker does not start.
- The system remains accessible for administration.

This test is particularly important because it verifies that Docker does not silently fall back to RootFS.

### 25.3 External Docker Data

Connect one valid external Docker Data filesystem to an image built with `None` mode.

Run:

```code
ravios-docker-data retry
```

Verify:

- The external partition is discovered.
- The candidate passes filesystem validation.
- The candidate is mounted at `/var/lib/docker`.
- Runtime status becomes `ready`.
- Docker starts successfully.

### 25.4 Internal Priority

Connect both:

- One valid Docker Data partition on the boot disk.
- One valid Docker Data partition on an external disk.

Verify that the valid internal candidate is selected.

The external candidate must not override the internal candidate.

### 25.5 Ambiguous Candidates

Test the following situations separately:

- Multiple valid candidates on the boot disk.
- Multiple valid external candidates with no valid boot-disk candidate.

In both cases, automatic discovery must report ambiguity.

Docker must remain stopped.

The manager must not select a candidate based on device enumeration order.

### 25.6 Invalid Candidates

Test partitions with:

- Incorrect filesystem UUID.
- Incorrect filesystem label.
- Unexpected filesystem type.
- Missing or unresolvable partition identity.
- Unresolvable parent disk identity.

Verify that invalid candidates are rejected and cannot become the active Docker Data destination.

## 26. Explicit Selection Tests

### 26.1 Selection Persistence

Select an external candidate:

```code
ravios-docker-data select /dev/sdb1
```

Verify that the selection is persisted using:

- `DISK_ID`
- `PARTUUID`

Reboot the system and confirm that the manager resolves the same partition.

The resolved Linux device name may differ after reboot. This must not affect selection.

### 26.2 Missing Selected Disk

After creating an explicit selection, disconnect the selected disk.

If another valid Docker Data filesystem is available, verify that RaviOS does not automatically switch to it.

Expected behavior:

- Explicit selection remains saved.
- Runtime status reports the selected destination as unavailable.
- Docker remains stopped.
- No automatic fallback occurs.

### 26.3 Restore Selected Disk

Reconnect the previously selected disk and run:

```code
ravios-docker-data retry
```

Verify that the manager resolves the original disk and partition using their stable identities.

The original Docker Data filesystem should become active again after successful validation.

### 26.4 Clear Explicit Selection

Run:

```code
ravios-docker-data clear
```

Verify that the explicit selection is removed and automatic discovery resumes.

The command must not format or erase any Docker Data filesystem.

## 27. Storage Switching Tests

Switching tests must verify both the storage state and the Docker service lifecycle.

### 27.1 Internal to External

Start with a valid internal Docker Data destination.

Connect a valid external destination and execute:

```code
ravios-docker-data change
```

Select the external destination.

Verify the operation follows this sequence:

1. Candidate discovery.
2. Candidate validation.
3. Operator selection.
4. Current mount identity verification.
5. Docker shutdown.
6. Current filesystem unmount.
7. New filesystem mount.
8. New mount verification.
9. Persistent selection update.
10. Docker startup validation.
11. Docker restart.

After the operation, verify:

```code
ravios-docker-data status
findmnt /var/lib/docker
```

The active mount must correspond to the selected external destination.

### 27.2 External to Internal

Repeat the switching test in the opposite direction.

This confirms that the management interface does not assume that the external disk is always the preferred destination.

### 27.3 Selecting the Current Destination

Execute `change` and select the already active destination.

Verify that the manager recognizes the destination as the current verified mount and exits without unnecessary operations.

Docker must not be stopped or restarted unnecessarily.

### 27.4 Switching Failure

These are recommended failure-injection tests. Not all failure scenarios have necessarily been exercised during routine VM validation.

Test failure scenarios where possible:

- Destination disappears after candidate enumeration.
- Destination validation fails.
- Docker cannot be stopped.
- Current filesystem cannot be unmounted.
- New filesystem cannot be mounted.
- New mount verification fails.
- Persistent selection cannot be updated.

The expected result is that Docker does not start against an uncertain destination.

The manager must report the failure and preserve enough state for diagnosis and recovery.

## 28. Docker Functional Validation

After storage is reported ready, validate Docker itself.

Inspect the Docker data root:

```code
docker info --format 'Docker Root Dir: {{.DockerRootDir}}'
```

Expected output:

```code
Docker Root Dir: /var/lib/docker
```

Run a functional container test:

```code
docker run --rm hello-world
```

The test must complete successfully.

However, a successful container execution is not sufficient proof of correct storage configuration.

Also verify:

```code
findmnt /var/lib/docker
lsblk -f
blkid
```

Confirm that:

- The expected partition is mounted.
- The filesystem type is ext4.
- The filesystem UUID and label match the designated identity.
- The active mount corresponds to the recorded `DISK_ID` and `PARTUUID`.

## 29. Troubleshooting Reference

The following commands are useful when diagnosing Docker Data issues.

### 29.1 Inspect Manager Status

```code
ravios-docker-data status
```

Use this as the first diagnostic step.

It reports the manager's current view of storage readiness and the selected destination.

### 29.2 List Candidates

```code
ravios-docker-data list
```

Use this to inspect available Docker Data candidates and identify invalid or ambiguous storage configurations.

### 29.3 Inspect Block Devices

```code
lsblk -f
```

Displays block devices, partitions, filesystem types, UUIDs, and labels.

### 29.4 Inspect Filesystem Identity

```code
blkid
```

Displays filesystem metadata, including UUID and label.

### 29.5 Inspect the Active Mount

```code
findmnt /var/lib/docker
```

Confirms whether the Docker data-root path is mounted and identifies the active source.

### 29.6 Inspect Persistent Device Links

```code
ls -l /dev/disk/by-id/
```

Useful for checking whether the selected stable disk identifier is available.

### 29.7 Retry Discovery

```code
ravios-docker-data retry
```

Use after connecting a missing disk or resolving a storage-related problem.

Do not manually edit runtime status to force Docker startup.

The manager and Docker init script must remain the authorities for storage readiness.

## 30. Static Validation and Code Review

Before accepting a change to this subsystem, perform static checks on all modified shell scripts.

For example:

```code
sh -n buildroot-external/rootfs-overlay/etc/init.d/S50docker-data
sh -n buildroot-external/rootfs-overlay/etc/init.d/S60dockerd
sh -n buildroot-external/rootfs-overlay/usr/sbin/ravios-docker-data

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\build.ps1),
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count -gt 0) {
    $errors | Format-List
    throw "PowerShell syntax validation failed."
}

```

Run the repository whitespace and patch validation check:

```code
git diff --check
```

Review all related changes together.

A storage-related change may affect multiple layers even when only one script appears to require modification.

At minimum, review:

- Build parameter handling.
- Image partition configuration.
- Buildroot post-image processing.
- Runtime discovery.
- Persistent selection.
- Mount handling.
- Docker startup validation.
- Management commands.
- Documentation.

Do not consider a change complete solely because its modified script passes a syntax check.

## 31. Change Impact Checklist

Before modifying the Docker Data subsystem, determine which parts of the storage contract are affected.

| Change                         | Components requiring review                                                               |
| ------------------------------ | ----------------------------------------------------------------------------------------- |
| Filesystem UUID change         | Discovery, validation, image generation, Docker startup gate, compatibility documentation |
| Filesystem label change        | Discovery, validation, image generation, Docker startup gate                              |
| Partition label change         | Image generation and candidate discovery                                                  |
| Mountpoint change              | Storage manager, Docker init script, Docker configuration, documentation                  |
| New discovery rule             | Candidate enumeration, classification, selection policy, tests                            |
| New persistent selection field | State serialization, state resolution, Docker startup validation                          |
| New management command         | CLI dispatch, validation, error handling, documentation                                   |
| New build mode                 | `build.ps1`, `post-image.sh`, Genimage configurations, build tests                        |
| Device identification changes  | Stable identity resolution, explicit selection, reboot and hardware tests                 |

A change to the on-disk identity contract must account for existing Docker Data filesystems.

A change to the runtime state format must account for every component that reads or writes that state.

A change to the discovery policy must include tests for ambiguous and invalid candidates.

## 32. Completion Criteria

A Docker Data subsystem change is complete only when all relevant conditions have been satisfied:

- The implementation preserves the separation between RootFS and Docker Data.
- No unsafe fallback to RootFS exists.
- Stable disk and partition identities are used for explicit selections.
- Automatic discovery remains deterministic.
- Ambiguous candidates are not selected automatically.
- Explicit selections do not silently fall back to other disks.
- Mount operations verify the resulting filesystem and mount source.
- Runtime ready status is published only after successful verification.
- Docker independently validates storage before starting.
- Storage failures do not prevent the base operating system from booting.
- Management operations do not format or erase existing Docker Data.
- Both build modes have been validated when affected.
- Relevant VM tests have passed.
- Static checks and code review have been completed.
- Documentation accurately reflects the implementation.

Do not commit or merge a storage-related change until its implementation, testing, and documentation have been reviewed.

## 33. Design Summary

The RaviOS Docker Data subsystem is built around one fundamental requirement:

Docker Engine may run only when RaviOS can prove that `/var/lib/docker` is backed by the intended, valid, and correctly mounted Docker Data filesystem.

The build system supports both internal Docker Data provisioning and minimal images without an internal data partition.

At runtime, the storage manager discovers existing compatible filesystems, applies deterministic selection rules, and mounts the chosen destination.

Explicit selections are persisted through stable disk and partition identities rather than transient Linux device names.

The management interface allows administrators to inspect candidates and change the active destination without formatting or deleting existing data.

Finally, the Docker init script independently validates the live storage state before allowing Docker Engine to start.

When storage cannot be verified, RaviOS remains available for administration while Docker stays stopped.

This fail-closed behavior is intentional and must remain a central invariant of future development.
