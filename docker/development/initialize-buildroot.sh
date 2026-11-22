#!/usr/bin/env bash
# Initialize the persistent Buildroot source volume exactly once.
# Existing source is never deleted or replaced automatically.
set -Eeuo pipefail

BUILDROOT_VERSION="${1:-2026.08.2}"
BUILDROOT_DIR="/workspace/buildroot"
DOWNLOAD_DIR="/workspace/dl"
ARCHIVE="${DOWNLOAD_DIR}/buildroot-${BUILDROOT_VERSION}.tar.gz"
URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"

if [[ ! "${BUILDROOT_VERSION}" =~ ^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$ ]]; then
    echo "ERROR: Invalid Buildroot version: ${BUILDROOT_VERSION}" >&2
    exit 2
fi

mkdir -p "${BUILDROOT_DIR}" "${DOWNLOAD_DIR}"

if [[ -f "${BUILDROOT_DIR}/Makefile" ]]; then
    CURRENT_VERSION="$(sed -n 's/^export BR2_VERSION := *//p' "${BUILDROOT_DIR}/Makefile" | head -n1)"
    if [[ "${CURRENT_VERSION}" != "${BUILDROOT_VERSION}" ]]; then
        echo "ERROR: Buildroot source already exists (${CURRENT_VERSION:-unknown}), requested ${BUILDROOT_VERSION}." >&2
        echo "No files were changed. Resolve the version mismatch manually." >&2
        exit 3
    fi
    echo "Buildroot ${CURRENT_VERSION} source already exists; reusing it."
    exit 0
fi

# Never overwrite a non-empty directory that is not a recognized Buildroot tree.
if [[ -n "$(find "${BUILDROOT_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "ERROR: ${BUILDROOT_DIR} is not empty but has no Buildroot Makefile." >&2
    echo "Refusing to delete or overwrite its contents." >&2
    exit 4
fi

if [[ -s "${ARCHIVE}" ]]; then
    echo "Using cached source archive: ${ARCHIVE}"
else
    echo "Downloading Buildroot ${BUILDROOT_VERSION} source..."
    PARTIAL="${ARCHIVE}.part"
    rm -f "${PARTIAL}"
    curl --fail --location --retry 3 --retry-delay 2 --output "${PARTIAL}" "${URL}"
    test -s "${PARTIAL}"
    mv "${PARTIAL}" "${ARCHIVE}"
fi

# Validate the cached/downloaded archive before extracting it into the volume.
if ! tar -tzf "${ARCHIVE}" >/dev/null; then
    echo "ERROR: Buildroot source archive is invalid: ${ARCHIVE}" >&2
    exit 5
fi

TMP_DIR="$(mktemp -d /tmp/ravios-buildroot.XXXXXX)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

tar -xzf "${ARCHIVE}" --strip-components=1 -C "${TMP_DIR}"
if [[ ! -f "${TMP_DIR}/Makefile" ]]; then
    echo "ERROR: Extracted archive does not contain a Buildroot Makefile." >&2
    exit 6
fi

EXTRACTED_VERSION="$(sed -n 's/^export BR2_VERSION := *//p' "${TMP_DIR}/Makefile" | head -n1)"
if [[ "${EXTRACTED_VERSION}" != "${BUILDROOT_VERSION}" ]]; then
    echo "ERROR: Archive version mismatch. Expected ${BUILDROOT_VERSION}, found ${EXTRACTED_VERSION:-unknown}." >&2
    exit 7
fi

# Copy only into the confirmed-empty persistent source volume.
cp -a "${TMP_DIR}/." "${BUILDROOT_DIR}/"
test -f "${BUILDROOT_DIR}/Makefile"
echo "Buildroot ${BUILDROOT_VERSION} initialized successfully in ${BUILDROOT_DIR}."
