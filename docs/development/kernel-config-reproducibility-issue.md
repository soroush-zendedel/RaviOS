# Kernel Configuration Reproducibility

## Issue title

Make the RaviOS kernel configuration self-contained and reproducible

## Issue type

Engineering / Build System / Reliability

## Status

Proposed

## Problem statement

RaviOS maintains a project-specific Linux kernel configuration at:

`buildroot-external/board/ravios/x86_64/linux.config`

Buildroot uses this file as the base configuration when configuring the
Linux kernel. The resulting kernel configuration is generated in the
Buildroot output tree:

`output/build/linux-<version>/.config`

These two files serve different purposes:

-   `linux.config` is the version-controlled input maintained by the
    RaviOS project.
-   `output/build/linux-<version>/.config` is the effective
    configuration produced after Buildroot and the Linux Kconfig system
    process that input.

The effective `.config` must not depend on stale output from an earlier
build. If a required kernel option is absent from the project
configuration, an old output tree may make the option appear enabled
because it was selected during an earlier build. A fresh configuration
can then disable it when Kconfig resolves dependencies.

This can cause features to compile incompletely or fail at runtime, even
when the corresponding top-level option appears to have been present in
an earlier build.

## Incident that exposed the problem

Docker image downloading worked, but starting a container failed with:

``` text
failed to create shim task
OCI runtime create failed
error setting cgroup config for procHooks process:
bpf_prog_query(BPF_CGROUP_DEVICE) failed: function not implemented
```

The investigation established the following:

1.  The RaviOS `linux.config` file contained `CONFIG_BPF_SYSCALL=y` and
    `CONFIG_CGROUP_BPF=y`, but did not contain `CONFIG_CGROUPS=y`.
2.  Buildroot copied the custom configuration and the configuration
    merge step preserved the requested options.
3.  Linux Kconfig then resolved the configuration. `CONFIG_CGROUP_BPF`
    depends on both `CONFIG_BPF_SYSCALL` and the cgroup subsystem being
    enabled.
4.  Since `CONFIG_CGROUPS` was not enabled in the base configuration,
    Kconfig disabled `CONFIG_CGROUP_BPF`.
5.  Adding `CONFIG_CGROUPS=y` to the project configuration, alongside
    the other required options, allowed all three options to remain
    enabled after Kconfig processing.
6.  A new image was built and booted. Docker successfully downloaded and
    ran the `hello-world` container.

The confirmed configuration is:

``` text
CONFIG_CGROUPS=y
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUP_BPF=y
```

This incident was not caused by `merge_config.sh`. It exposed that the
project-maintained kernel configuration did not explicitly declare a
required dependency.

## Goal

Make the version-controlled kernel configuration a reliable,
self-contained declaration of the kernel capabilities required by
RaviOS.

A clean build must produce the required effective kernel configuration
without relying on:

-   an earlier Buildroot output directory;
-   a previously generated Linux `.config`;
-   options left enabled by an earlier interactive configuration;
-   undocumented manual changes inside the output tree.

The goal is not to copy every possible Linux kernel option into
`linux.config`. It is to explicitly maintain the options required by the
features RaviOS supports, including their relevant Kconfig dependencies.

## Proposed implementation

### 1. Treat `linux.config` as the authoritative project input

Keep the kernel configuration in:

`buildroot-external/board/ravios/x86_64/linux.config`

This file must remain version-controlled.

Permanent kernel configuration changes must be made in this source file
or in an explicitly declared, version-controlled configuration fragment.
Do not treat this generated file as the permanent source of
configuration:

`output/build/linux-<version>/.config`

The generated `.config` is an output to inspect and validate, not the
place to maintain project changes.

### 2. Maintain configuration requirements by feature

For every feature added to RaviOS that depends on kernel capabilities:

1.  Identify the kernel options required by the feature.
2.  Check the relevant Linux Kconfig definitions and dependencies for
    the exact kernel version used by RaviOS.
3.  Add the required options and their necessary dependencies to the
    project configuration.
4.  Reconfigure the kernel.
5.  Inspect the resulting `.config` to verify that the requested options
    survived Kconfig processing.
6.  Run a functional test of the feature in a newly built RaviOS image.

Do not assume that enabling one visible option automatically enables all
of its dependencies.

For example, enabling `CONFIG_CGROUP_BPF` requires the relevant cgroup
and BPF prerequisites. The Docker incident demonstrated why those
dependencies must be explicit in the project configuration.

### 3. Keep configuration fragments deliberate

RaviOS currently uses a custom kernel configuration file and has no
configured kernel fragments.

If the project later introduces fragments, each fragment must be:

-   stored in the repository;
-   referenced explicitly by the Buildroot configuration;
-   named and documented according to the feature or board purpose it
    serves;
-   included in the same validation process as the base configuration.

Fragments should organize configuration, not become an undocumented
substitute for a complete and reproducible project configuration.

When the same symbol appears in multiple inputs, its final value must be
understood and verified. Do not rely on accidental ordering or stale
output.

### 4. Validate the effective configuration after Kconfig

After changing kernel configuration inputs, run the Buildroot kernel
reconfiguration target:

``` sh
make -C /workspace/buildroot \
    O=/workspace/output \
    BR2_EXTERNAL=/workspace/buildroot-external \
    linux-reconfigure
```

Then inspect the effective kernel configuration:

``` sh
grep -E '^(CONFIG_CGROUPS|CONFIG_BPF_SYSCALL|CONFIG_CGROUP_BPF)=' \
    /workspace/output/build/linux-7.3.3/.config
```

For the Docker cgroup BPF requirement, the expected result is:

``` text
CONFIG_CGROUPS=y
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUP_BPF=y
```

A requested option missing from the resulting `.config` must be treated
as a configuration failure to investigate. Do not assume that a
successful `linux-reconfigure` command means every requested option
remained enabled.

### 5. Prove clean-build reproducibility

A reconfiguration in an existing output directory is useful, but it does
not by itself prove that the project configuration is self-contained.
The output directory may contain state from earlier builds.

Add a clean-build validation step to the development workflow:

1.  Preserve the existing working build and artifacts.
2.  Configure a separate, fresh Buildroot output directory using the
    committed RaviOS defconfig and external tree.
3.  Build the Linux kernel and the RaviOS image using that fresh output
    directory.
4.  Inspect the generated kernel `.config`.
5.  Verify all required kernel options.
6.  Boot the resulting image and run the relevant functional tests.

The clean test must start without a previously generated Linux
`.config`. Do not delete a developer's existing output directory as part
of a routine validation command.

The exact fresh-output build command should be documented after it has
been tested with the repository's current `build.ps1` workflow. The
validation must use the same RaviOS defconfig, Buildroot version,
external tree, and declared configuration inputs as the normal build.

### 6. Add automated configuration checks

As a follow-up implementation, add a small validation script or build
check that reads the generated Linux `.config` and verifies a curated
list of mandatory symbols.

For example, the Docker-related check should fail if any of these are
absent or not set to `y`:

-   `CONFIG_CGROUPS`
-   `CONFIG_BPF_SYSCALL`
-   `CONFIG_CGROUP_BPF`

The check should:

-   inspect the generated `.config`, not merely search the source file;
-   distinguish `=y` from `=m` and `# CONFIG_X is not set`;
-   print the missing or incorrectly configured symbol;
-   return a non-zero exit status on failure;
-   be easy to extend when RaviOS gains more kernel-dependent features.

The required-symbol list should be maintained deliberately. It should
not be generated by blindly copying every option from a particular
build's `.config`.

### 7. Document why an option may disappear

When a requested option does not appear in the final `.config`,
investigate the Kconfig dependency chain before blaming Buildroot's
merge process.

The relevant stages are:

1.  Buildroot selects and copies the configured base kernel
    configuration.
2.  Buildroot merges any declared configuration fragments.
3.  Kconfig processes the merged input and resolves dependencies,
    defaults, choices, and constraints (including `olddefconfig`).
4.  Buildroot's kernel-specific configuration fixups may apply
    additional changes.
5.  The resulting `.config` is used for the kernel build.

The exact ordering and implementation should be checked against the
Buildroot version in use when investigating a future issue. A successful
merge does not guarantee that every requested option will remain enabled
after Kconfig processing.

## Acceptance criteria

This issue can be closed when all of the following are true:

-   [ ] `linux.config` is the documented, version-controlled source of
    RaviOS kernel configuration.
-   [ ] Required kernel options and their relevant dependencies are
    explicitly maintained.
-   [ ] Any future kernel fragments are version-controlled, declared,
    and documented.
-   [ ] The effective Linux `.config` is checked after Kconfig
    processing.
-   [ ] A clean build from a fresh output directory produces the
    required kernel configuration.
-   [ ] A validation check reports missing or incorrectly configured
    mandatory symbols.
-   [ ] Docker's required cgroup BPF options are verified in the
    generated `.config`.
-   [ ] The clean-built RaviOS image boots and passes the Docker
    container execution test.

## Scope and non-goals

This issue is about kernel configuration correctness and
reproducibility.

It does not propose:

-   enabling every Linux kernel feature;
-   replacing Buildroot or the current RaviOS build architecture;
-   maintaining generated output `.config` files in Git;
-   adding unrelated kernel hardening options;
-   assuming that all package dependencies are kernel dependencies.

Only kernel capabilities required by RaviOS features and supported
hardware should be enabled.

## Current state

Already completed:

-   [x] The Docker-related missing `CONFIG_CGROUPS=y` dependency was
    identified.
-   [x] `CONFIG_CGROUPS=y`, `CONFIG_BPF_SYSCALL=y`, and
    `CONFIG_CGROUP_BPF=y` were added to the RaviOS kernel configuration.
-   [x] Buildroot kernel reconfiguration completed.
-   [x] All three options were confirmed enabled in the generated Linux
    `.config`.
-   [x] A newly built RaviOS image booted successfully.
-   [x] `docker run --rm hello-world` completed successfully.

Still to do:

-   [ ] Define and document the clean-output build procedure.
-   [ ] Add automated mandatory-kernel-option validation.
-   [ ] Validate the procedure from a fresh output directory.
-   [ ] Add the workflow to the RaviOS development documentation.
