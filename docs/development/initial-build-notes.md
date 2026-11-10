# Initial Build Notes

## Overview

This document records issues and observations encountered
during the first RaviOS Buildroot build.

These notes are based on the initial development environment
and should be verified before becoming permanent build rules.

## 1. Package Source Availability

Some package sources required during the Buildroot build
were unavailable from their expected download locations.

Packages and components observed:

- fakeroot
- Linux kernel
- glibc

In some cases, the original source archives had to be
located and downloaded manually.

### Follow-up

- Identify the exact failing package URLs.
- Check whether the upstream source was moved or removed.
- Verify Buildroot download mirrors and fallback mechanisms.
- Document reliable alternative download locations.
- Avoid modifying package source versions without
  checking their hashes and Buildroot compatibility.

## 2. glibc Git Download Behavior

The glibc source retrieval process appeared unusually
time-consuming.

Instead of downloading a ready-made source archive,
the process appeared to retrieve a Git repository and
locate a specific commit.

This raised concerns about the amount of Git history
being downloaded.

### Follow-up

- Inspect the Buildroot glibc download configuration.
- Determine whether a full Git history is being fetched.
- Check whether a release tarball or shallow clone
  can be used instead.
- Measure actual download time and repository size.

Note: Fetching Git history and compiling Git commits
are different operations. The actual build process
must be inspected before concluding that multiple
commits are being compiled.

## 3. Docker Bind Mount Performance

The current development environment synchronizes the
project directory between the Windows host and the
Docker container.

Buildroot generates and accesses a very large number
of files during compilation.

Performing these operations through a Windows-hosted
bind mount significantly reduced build performance.

The current setup exposes more of the build filesystem
to the host than necessary.

### Proposed Improvement

Keep the following directories inside Docker-managed
Linux filesystem storage:

- Buildroot source tree
- Buildroot output directory
- Download cache
- Intermediate build files

Only expose final build artifacts to the host.

For example:

- Final ISO images
- Final disk images
- Optional build reports

Docker named volumes can be used for persistent
build storage.

## 4. Lessons Learned

The development environment should prioritize:

1. Reproducible builds.
2. Native Linux filesystem performance inside Docker.
3. Persistent Buildroot download caching.
4. Minimal host/container filesystem synchronization.
5. Easy access to final build artifacts.