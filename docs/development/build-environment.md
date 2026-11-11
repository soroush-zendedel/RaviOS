
# Build Environment

This document describes the RaviOS Buildroot development environment and provides instructions for handling source packages that cannot be downloaded automatically.

## Development environment

RaviOS uses Docker to provide an isolated Buildroot development environment.

The Buildroot download cache is stored in a persistent Docker volume:

```text
buildroot-dl:/workspace/dl
```

The Buildroot configuration uses:

```text
BR2_DL_DIR="/workspace/dl"
```

Downloaded source archives are cached between builds and do not need to be downloaded again unless the cache is unavailable or incomplete.

## Manually downloading source packages

In some environments, Buildroot may fail to download source archives because of network restrictions, unavailable mirrors, or connection problems.

In these cases, packages can be downloaded manually on the host and copied into the Buildroot download cache.

### 1. Download the required archive

Download the exact archive requested by Buildroot.

Keep its original filename unchanged.

For convenience, manually downloaded archives can be stored temporarily in:

```text
D:\RaviOS\download_tmp
```

This directory is local to the development environment and should not be committed to Git.

### 2. Copy the archive into the container

Buildroot organizes downloaded packages into package-specific subdirectories inside `BR2_DL_DIR`.

For example, the Fakeroot archive must be placed at:

```text
/workspace/dl/fakeroot/fakeroot_1.37.2.orig.tar.gz
```

First, create the destination directory:

```powershell
docker exec ravios-dev mkdir -p /workspace/dl/fakeroot
```

Then copy the archive:

```powershell
docker cp .\fakeroot_1.37.2.orig.tar.gz ravios-dev:/workspace/dl/fakeroot/fakeroot_1.37.2.orig.tar.gz
```

Run these commands from the `download_tmp` directory.

### 3. Verify the copied archive

Check that the archive exists inside the container:

```bash
ls -lh /workspace/dl/fakeroot/
```

Buildroot can then use the cached archive during the next build.

Buildroot's package integrity checks should still be allowed to run. Do not rename archives or bypass checksum verification to work around download failures.

## Examples from the current build

The following archives were manually downloaded during the initial RaviOS build:

| Package | Archive |
|---|---|
| ACL | `acl-2.4.0.tar.xz` |
| Attr | `attr-2.6.0.tar.xz` |
| Bzip2 | `bzip2-1.0.8.tar.gz` |
| Elfutils | `elfutils-0.195.tar.bz2` |
| Fakeroot | `fakeroot_1.37.2.orig.tar.gz` |
| Libarchive | `libarchive-3.8.9.tar.xz` |

These are examples from the current development environment, not a permanent list of required manual downloads. The actual packages depend on the Buildroot configuration and available download mirrors.

## Important notes

- Use the exact filename expected by Buildroot.
- Copy archives into the package-specific directory under `/workspace/dl`.
- Do not place downloaded archives directly in the Git repository.
- The download cache is persistent and shared through the Docker volume.
- Do not delete the download cache as a routine troubleshooting step.
- Prefer official upstream sources and preserve Buildroot's checksum verification.


## RaviOS Manual Download Archive

Some source packages required by the current Buildroot configuration may be difficult to download because of network restrictions or unavailable upstream mirrors.

To make development easier, a shared archive of manually downloaded source packages is available on Google Drive.

**[RaviOS Manual Download Archive](https://drive.google.com/drive/folders/1lp17ytDCbXHLmG3rtAENCf5rXCCR_BHQ?usp=drive_link)**

### Available archives

| Package | Archive |
|---|---|
| ACL | `acl-2.4.0.tar.xz` |
| Attr | `attr-2.6.0.tar.xz` |
| Bzip2 | `bzip2-1.0.8.tar.gz` |
| Elfutils | `elfutils-0.195.tar.bz2` |
| Fakeroot | `fakeroot_1.37.2.orig.tar.gz` |
| Libarchive | `libarchive-3.8.9.tar.xz` |

These archives were manually downloaded during RaviOS development and are provided as a convenience for other developers.

### Usage

1. Download the required archive from the shared Google Drive folder.
2. Keep its original filename unchanged.
3. Copy it into the appropriate package directory inside `/workspace/dl`.

For example, to provide the Fakeroot archive:

```powershell
docker exec ravios-dev mkdir -p /workspace/dl/fakeroot

docker cp .\fakeroot_1.37.2.orig.tar.gz `
    ravios-dev:/workspace/dl/fakeroot/fakeroot_1.37.2.orig.tar.gz
```

Buildroot will use the cached archive when building the corresponding package.

**Important:** The shared archive is a convenience mirror, not an official upstream source. Buildroot's package integrity and checksum verification should remain enabled.

# Cheat Code

```bash
docker exec ravios-dev mkdir -p `
    /workspace/dl/acl `
    /workspace/dl/attr `
    /workspace/dl/bzip2 `
    /workspace/dl/elfutils `
    /workspace/dl/fakeroot `
    /workspace/dl/libarchive

docker cp .\acl-2.4.0.tar.xz ravios-dev:/workspace/dl/acl/
docker cp .\attr-2.6.0.tar.xz ravios-dev:/workspace/dl/attr/
docker cp .\bzip2-1.0.8.tar.gz ravios-dev:/workspace/dl/bzip2/
docker cp .\elfutils-0.195.tar.bz2 ravios-dev:/workspace/dl/elfutils/
docker cp .\fakeroot_1.37.2.orig.tar.gz ravios-dev:/workspace/dl/fakeroot/
docker cp .\libarchive-3.8.9.tar.xz ravios-dev:/workspace/dl/libarchive/
```