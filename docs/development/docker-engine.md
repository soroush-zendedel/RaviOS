# Docker Engine Integration

This document records the Docker Engine integration work and the
validation completed on RaviOS.

## 1. Overview

RaviOS builds Docker Engine into its Buildroot-based operating system
image. Docker is intended to be available immediately after
installation, without a separate post-install download or installation
step.

### Tested environment

-   Buildroot: 2026.08.1
-   Linux kernel: 7.3.3
-   Docker Engine package: 28.5.2
-   Architecture: x86_64
-   Container runtime: runc
-   Storage driver: overlay2
-   Cgroup version: 2
-   Docker data filesystem: ext4
-   Test environment: VirtualBox

## 2. Buildroot Integration

Docker Engine is provided by Buildroot's `docker-engine` package.

The package brings in dependencies including:

-   containerd
-   iptables
-   libseccomp
-   cgroupfs-v2-mount

The Docker daemon is integrated into the RaviOS startup process.

## 3. Kernel Configuration

### 3.1 Initial failure

The first image pull from Docker Hub succeeded, but starting the
container failed with:

``` text
failed to create shim task
OCI runtime create failed
error setting cgroup config for procHooks process:
bpf_prog_query(BPF_CGROUP_DEVICE) failed: function not implemented
```

This indicated that the kernel did not have the required cgroup BPF
support enabled.

### 3.2 Configuration correction

The following kernel options were added to the RaviOS kernel
configuration:

``` text
CONFIG_CGROUPS=y
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUP_BPF=y
```

Configuration file:

`buildroot-external/board/ravios/x86_64/linux.config`

The kernel was reconfigured through Buildroot:

``` sh
make -C /workspace/buildroot \
    O=/workspace/output \
    BR2_EXTERNAL=/workspace/buildroot-external \
    linux-reconfigure
```

The generated kernel configuration was checked, and all three options
were confirmed enabled:

``` text
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_BPF=y
```

A new RaviOS image was built and booted in VirtualBox. The container
execution test then succeeded.

## 4. TLS Certificate Support

Docker Hub access initially required correcting the CA certificate
bundle.

The Debian CA certificate archive used by the Buildroot package was
manually downloaded from a mirror after the cached archive was found to
be empty.

The downloaded archive was verified with this SHA-256 checksum:

``` text
914416a1e44a25733aff51092fe4e27fdec1c9f6e8d1db0b8364922486153134
```

The resulting certificate bundle was installed at:

`/etc/ssl/certs/ca-certificates.crt`

Its observed size was approximately 176.5 KiB.

After this correction, TLS communication with Docker Hub worked.

## 5. Docker Data Partition

Docker's persistent data directory is:

`/var/lib/docker`

RaviOS is designed to keep Docker data on a dedicated ext4 partition,
separate from the operating system RootFS.

The designated filesystem identity is:

-   UUID: `66666666-6666-6666-6666-666666666666`
-   Label: `revayat`

The data partition is intended to be reusable across RaviOS
installations and versions, including when it is attached as an external
disk.

**Important design requirement:** if no valid Docker Data filesystem is
available, Docker must not silently fall back to storing data in RootFS.

## 6. Validation Results

The following tests were completed on the newly built RaviOS image.

### 6.1 Docker daemon and configuration

Docker daemon started successfully.

The reported configuration included:

-   Storage driver: `overlay2`
-   Cgroup driver: `cgroupfs`
-   Cgroup version: `2`
-   Docker Root Dir: `/var/lib/docker`

### 6.2 Image download and container execution

Command:

``` sh
docker run --rm hello-world
```

Result:

-   The `hello-world:latest` image was downloaded from Docker Hub.
-   Docker created and started the container.
-   The container printed `Hello from Docker!`.
-   The command completed successfully.

This verified image downloading, TLS connectivity, container creation,
and runtime execution.

### 6.3 Docker Data mount

Command:

``` sh
findmnt /var/lib/docker
```

Observed output:

``` text
TARGET          SOURCE    FSTYPE OPTIONS
/var/lib/docker /dev/sda3 ext4   rw,relatime
```

Docker's configured data directory was also checked:

``` sh
docker info --format '{{.DockerRootDir}}'
```

Observed output:

``` text
/var/lib/docker
```

Together, these checks confirmed that Docker was using the dedicated
ext4 partition mounted at `/var/lib/docker`, rather than a directory on
RootFS.

### 6.4 Persistence after reboot

Before reboot, `docker image ls` showed:

``` text
REPOSITORY    TAG       IMAGE ID       CREATED        SIZE
hello-world   latest    e2ac70e7319a   7 months ago   10.1kB
```

RaviOS was rebooted. After reconnecting over SSH, `docker image ls`
showed the same `hello-world:latest` image with the same image ID:

`e2ac70e7319a`

This confirmed that the downloaded image persisted across a system
reboot.

## 7. Remaining Tests

The following Docker Data scenarios have **not yet been validated**:

1.  Shut down the VM and temporarily detach or make the Docker Data
    partition unavailable.
2.  Boot RaviOS without a valid Docker Data filesystem.
3.  Verify that Docker does not start with its data directory on RootFS.
4.  Verify that the missing data partition is handled safely and
    clearly.
5.  Reattach the data partition and verify that its existing data is
    reused without formatting.

These tests are required before Docker Data handling can be considered
fully validated.

## 8. Current Status

### Confirmed

-   Docker Engine is included in the Buildroot image.
-   The required cgroup BPF kernel options are enabled.
-   TLS communication with Docker Hub works.
-   The `hello-world` container runs successfully.
-   Docker uses the dedicated ext4 data partition.
-   The downloaded Docker image survives a system reboot.

### Pending

-   Safe behavior when Docker Data is unavailable.
-   Reuse and recovery after detaching and reattaching the data
    partition.
