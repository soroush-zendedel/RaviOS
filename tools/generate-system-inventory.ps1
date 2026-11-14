[CmdletBinding()]
param(
    [string]$Container = "ravios-dev",
    [string]$BuildId = "manual",
    [ValidateSet("None", "Create", "Unknown")]
    [string]$DockerDataMode = "Unknown",
    [string]$DiskSize = "Automatic",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ProjectRoot "docs\system-inventory.md"
}

$OutputDirectory = Split-Path -Parent $OutputPath
$TempPath = "$OutputPath.$PID.tmp"

function Get-DockerOutput {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $Result = & docker @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Arguments -join ' ')`n$($Result -join "`n")"
    }

    return ($Result -join "`n")
}

function Get-ConfigValue {
    param(
        [string]$Config,
        [string]$Key
    )

    $Pattern = "(?m)^$([regex]::Escape($Key))=(.*)$"
    $Match = [regex]::Match($Config, $Pattern)

    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim('"')
    }

    return "Not set"
}

function Get-PackageCategory {
    param([string]$Name)

    switch -Regex ($Name) {
        '^(docker-engine|docker-cli|containerd|runc|cgroupfs-v2-mount)$' {
            return "Container Platform"
        }
        '^(linux|linux-firmware|wireless-regdb|wpa_supplicant|connman|ifupdown-scripts|iptables)$' {
            return "Kernel and Networking"
        }
        '^(e2fsprogs|util-linux|kmod|grub2)$' {
            return "Storage and System Tools"
        }
        '^(dropbear|ca-certificates|acpid|eudev|dbus|initscripts|urandom-scripts|skeleton.*)$' {
            return "System Services"
        }
        '^(glibc|gcc-final|toolchain|lib.*|ncurses|readline|expat|pcre2|zlib)$' {
            return "Libraries and Toolchain"
        }
        '^(busybox)$' {
            return "Core Utilities"
        }
        default {
            return "Other"
        }
    }
}

function Get-KernelCategory {
    param([string]$Name)

    switch -Regex ($Name) {
        '^CONFIG_(CGROUP|NAMESPACES|UTS_NS|IPC_NS|PID_NS|NET_NS|USER_NS|SECCOMP|BPF|SECURITY)' {
            return "Containers, Isolation and Security"
        }
        '^CONFIG_(NET|NF_|IP_|IPV6|BRIDGE|VETH|WIREGUARD|TUN)' {
            return "Networking"
        }
        '^CONFIG_(EXT|OVERLAY|FUSE|SQUASHFS|TMPFS|NFS|CIFS|FAT|VFAT|ISO9660|BTRFS|XFS)' {
            return "Filesystems"
        }
        '^CONFIG_(ATA|SATA|SCSI|BLK|NVME|MD|DM_|MMC|VIRTIO_BLK)' {
            return "Storage and Block Devices"
        }
        '^CONFIG_(USB|HID|INPUT|I2C|SPI|GPIO)' {
            return "USB and Input Devices"
        }
        '^CONFIG_(PCI|ACPI|EFI|X86|CPU|SMP|HYPERVISOR|PARAVIRT)' {
            return "Hardware and Architecture"
        }
        '^CONFIG_(VIRTIO|KVM|VHOST)' {
            return "Virtualization"
        }
        '^CONFIG_(DRM|FB|SOUND|SND|VIDEO)' {
            return "Graphics and Audio"
        }
        '^CONFIG_(CFG80211|MAC80211|ATH|IWL|RT2|RTL|WLAN)' {
            return "Wireless"
        }
        '^CONFIG_(MODULE|MODVERSIONS|KMOD)' {
            return "Kernel Modules"
        }
        '^CONFIG_(CRYPTO|ASYMMETRIC|KEYS)' {
            return "Cryptography"
        }
        '^CONFIG_(SERIAL|TTY|VT|CONSOLE)' {
            return "Console and Serial"
        }
        '^CONFIG_(POWER|THERMAL|HWMON|WATCHDOG)' {
            return "Power and Monitoring"
        }
        default {
            return "Other Kernel Features"
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $BuildConfig = Get-DockerOutput @(
        "exec", $Container, "cat", "/workspace/output/.config"
    )

    $KernelConfig = Get-DockerOutput @(
        "exec", $Container, "cat", "/workspace/output/build/linux-7.3.3/.config"
    )

    $BusyBoxConfig = Get-DockerOutput @(
        "exec", $Container, "cat", "/workspace/output/build/busybox-1.38.0/.config"
    )

    $PackageFileList = Get-DockerOutput @(
        "exec", $Container, "cat", "/workspace/output/build/packages-file-list.txt"
    )

    $BuildrootVersionOutput = Get-DockerOutput @(
        "exec", $Container, "grep", "^export BR2_VERSION :=", "/workspace/buildroot/Makefile"
    )

    $BuildDirectoriesOutput = Get-DockerOutput @(
        "exec", $Container, "find", "/workspace/output/build",
        "-mindepth", "1", "-maxdepth", "1", "-type", "d"
    )

    $BusyBoxLinksOutput = Get-DockerOutput @(
        "exec", $Container, "find", "/workspace/output/target",
        "-type", "l", "-lname", "*busybox*"
    )

    $StandaloneExecutablesOutput = Get-DockerOutput @(
        "exec", $Container, "find",
        "/workspace/output/target/bin",
        "/workspace/output/target/sbin",
        "/workspace/output/target/usr/bin",
        "/workspace/output/target/usr/sbin",
        "-type", "f", "-executable"
    )

    $StandaloneSymlinksOutput = Get-DockerOutput @(
        "exec", $Container, "find",
        "/workspace/output/target/bin",
        "/workspace/output/target/sbin",
        "/workspace/output/target/usr/bin",
        "/workspace/output/target/usr/sbin",
        "-type", "l", "!", "-lname", "*busybox*"
    )

    $GenimageFilesOutput = Get-DockerOutput @(
        "exec", $Container, "find", "/workspace/output/images",
        "-maxdepth", "1", "-type", "f", "-name", "genimage*.cfg"
    )

    $BuildrootVersion = "Unknown"
    if ($BuildrootVersionOutput -match 'BR2_VERSION\s*:=\s*(\S+)') {
        $BuildrootVersion = $Matches[1]
    }

    $BuildDirectories = @(
        $BuildDirectoriesOutput -split "`r?`n" |
            Where-Object { $_ -and (Split-Path $_ -Leaf) -notlike "host-*" } |
            ForEach-Object { Split-Path $_ -Leaf }
    )

    $PackageNames = @(
        $PackageFileList -split "`r?`n" |
            Where-Object { $_ -match '^[^,]+,' } |
            ForEach-Object { ($_ -split ",", 2)[0].Trim() } |
            Sort-Object -Unique
    )

    $Packages = foreach ($PackageName in $PackageNames) {
        $ExactDirectory = $BuildDirectories |
            Where-Object { $_ -eq $PackageName } |
            Select-Object -First 1

        if ($ExactDirectory) {
            $Version = "Unversioned"
        }
        else {
            $Prefix = "$PackageName-"
            $MatchingDirectory = $BuildDirectories |
                Where-Object {
                    $_.StartsWith($Prefix, [StringComparison]::Ordinal) -and
                    $_.Substring($Prefix.Length) -match '^\d'
                } |
                Sort-Object Length -Descending |
                Select-Object -First 1

            if ($MatchingDirectory) {
                $Version = $MatchingDirectory.Substring($Prefix.Length)
            }
            else {
                $Version = "Not available"
            }
        }

        [PSCustomObject]@{
            Name     = $PackageName
            Version  = $Version
            Category = Get-PackageCategory $PackageName
        }
    }

    $BusyBoxApplets = @(
        $BusyBoxLinksOutput -split "`r?`n" |
            Where-Object { $_ } |
            ForEach-Object {
                $RelativePath = $_ -replace '^/workspace/output/target', ''
                [PSCustomObject]@{
                    Name = Split-Path $_ -Leaf
                    Path = $RelativePath
                }
            } |
            Sort-Object Path -Unique
    )

    $StandaloneExecutables = @(
        $StandaloneExecutablesOutput -split "`r?`n" |
            Where-Object { $_ } |
            ForEach-Object { $_ -replace '^/workspace/output/target', '' } |
            Sort-Object -Unique
    )

    $StandaloneSymlinks = @(
        $StandaloneSymlinksOutput -split "`r?`n" |
            Where-Object { $_ } |
            ForEach-Object { $_ -replace '^/workspace/output/target', '' } |
            Sort-Object -Unique
    )

    $KernelOptions = @(
        [regex]::Matches(
            $KernelConfig,
            '(?m)^(CONFIG_[A-Z0-9_]+)=(y|m)$'
        ) | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.Groups[1].Value
                Value    = $_.Groups[2].Value
                Category = Get-KernelCategory $_.Groups[1].Value
            }
        } | Sort-Object Category, Name
    )

    $KernelVersion = "Unknown"
    $KernelDirectory = $BuildDirectories |
        Where-Object { $_ -match '^linux-\d' } |
        Select-Object -First 1

    if ($KernelDirectory) {
        $KernelVersion = $KernelDirectory -replace '^linux-', ''
    }

    $BusyBoxVersion = "Unknown"
    $BusyBoxDirectory = $BuildDirectories |
        Where-Object { $_ -match '^busybox-\d' } |
        Select-Object -First 1

    if ($BusyBoxDirectory) {
        $BusyBoxVersion = $BusyBoxDirectory -replace '^busybox-', ''
    }

    $DockerVersion = "Not found"
    $DockerPackage = $Packages |
        Where-Object { $_.Name -eq "docker-engine" } |
        Select-Object -First 1

    if ($DockerPackage) {
        $DockerVersion = $DockerPackage.Version
    }

    $UserNamespaces = Get-ConfigValue $KernelConfig "CONFIG_USER_NS"
    $DockerEngineEnabled = Get-ConfigValue $BuildConfig "BR2_PACKAGE_DOCKER_ENGINE"
    $DockerCliEnabled = Get-ConfigValue $BuildConfig "BR2_PACKAGE_DOCKER_CLI"
    $Hostname = Get-ConfigValue $BuildConfig "BR2_TARGET_GENERIC_HOSTNAME"
    $RootFsSize = Get-ConfigValue $BuildConfig "BR2_TARGET_ROOTFS_EXT2_SIZE"

    $GenimageReport = @()
    $GenimagePaths = @(
        $GenimageFilesOutput -split "`r?`n" |
            Where-Object { $_ }
    )

    foreach ($GenimagePath in $GenimagePaths) {
        $GenimageContent = Get-DockerOutput @(
            "exec", $Container, "cat", $GenimagePath
        )

        $GenimageReport += "### $(Split-Path $GenimagePath -Leaf)"
        $GenimageReport += '```text'
        $GenimageReport += $GenimageContent
        $GenimageReport += '```'
        $GenimageReport += ""
    }

    $Lines = [System.Collections.Generic.List[string]]::new()

    $Lines.Add("# RaviOS System Inventory")
    $Lines.Add("")
    $Lines.Add("> Automatically generated from the Buildroot output. Do not edit this file manually.")
    $Lines.Add("")
    $Lines.Add("## Build Overview")
    $Lines.Add("")
    $Lines.Add("| Property | Value |")
    $Lines.Add("|---|---|")
    $Lines.Add("| Build ID | $BuildId |")
    $Lines.Add("| Generated | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') |")
    $Lines.Add("| Hostname | $Hostname |")
    $Lines.Add("| Buildroot | $BuildrootVersion |")
    $Lines.Add("| Linux Kernel | $KernelVersion |")
    $Lines.Add("| BusyBox | $BusyBoxVersion |")
    $Lines.Add("| Docker Engine | $DockerVersion |")
    $Lines.Add("| Docker Data mode | $DockerDataMode |")
    $Lines.Add("| Requested disk size | $DiskSize |")
    $Lines.Add("| RootFS configured size | $RootFsSize |")
    $Lines.Add("")
    $Lines.Add("## Platform Summary")
    $Lines.Add("")
    $Lines.Add("| Component | Build configuration |")
    $Lines.Add("|---|---|")
    $Lines.Add("| Docker Engine | $DockerEngineEnabled |")
    $Lines.Add("| Docker CLI | $DockerCliEnabled |")
    $Lines.Add("| Kernel User Namespaces | $UserNamespaces |")
    $Lines.Add("| Installed Target packages | $($Packages.Count) |")
    $Lines.Add("| BusyBox applet links | $($BusyBoxApplets.Count) |")
    $Lines.Add("| Standalone executable files | $($StandaloneExecutables.Count) |")
    $Lines.Add("| Non-BusyBox symbolic links | $($StandaloneSymlinks.Count) |")
    $Lines.Add("| Active Kernel options (`=y` or `=m`) | $($KernelOptions.Count) |")
    $Lines.Add("")
    $Lines.Add("## Important Notes")
    $Lines.Add("")
    $Lines.Add("- Build configuration and installed files are reported separately.")
    $Lines.Add("- Kernel options are taken from the final generated Kernel configuration.")
    $Lines.Add("- BusyBox applets are identified through installed symbolic links to BusyBox.")
    $Lines.Add("- Standalone executables exclude symbolic links that point to BusyBox.")
    $Lines.Add("- Runtime behavior is not inferred from build-time configuration.")
    $Lines.Add("- Runtime verification has not been collected by this generator.")
    $Lines.Add("")

    $Lines.Add("## Installed Target Packages")
    $Lines.Add("")

    foreach ($Category in ($Packages.Category | Sort-Object -Unique)) {
        $Lines.Add("### $Category")
        $Lines.Add("")
        $Lines.Add("| Package | Version |")
        $Lines.Add("|---|---|")

        foreach ($Package in ($Packages | Where-Object Category -eq $Category | Sort-Object Name)) {
            $Lines.Add("| $($Package.Name) | $($Package.Version) |")
        }

        $Lines.Add("")
    }

    $Lines.Add("## BusyBox Applets")
    $Lines.Add("")
    $Lines.Add("These entries are installed symbolic links pointing to the BusyBox executable.")
    $Lines.Add("")
    $Lines.Add("| Applet | Installed path |")
    $Lines.Add("|---|---|")

    foreach ($Applet in $BusyBoxApplets) {
        $Lines.Add("| $($Applet.Name) | ``$($Applet.Path)`` |")
    }

    $Lines.Add("")
    $Lines.Add("## Standalone Executable Files")
    $Lines.Add("")
    $Lines.Add("Regular executable files found in the standard command directories.")
    $Lines.Add("")

    foreach ($Tool in $StandaloneExecutables) {
        $Lines.Add("- ``$Tool``")
    }

    $Lines.Add("")
    $Lines.Add("## Non-BusyBox Symbolic Links")
    $Lines.Add("")
    $Lines.Add("Installed symbolic links in the standard command directories that do not point to BusyBox.")
    $Lines.Add("")
    $Lines.Add("| Link | Installed path |")
    $Lines.Add("|---|---|")

    foreach ($Link in $StandaloneSymlinks) {
        $Lines.Add("| $(Split-Path $Link -Leaf) | ``$Link`` |")
    }

    $Lines.Add("")
    $Lines.Add("## Enabled Kernel Configuration Options")
    $Lines.Add("")
    $Lines.Add("The following list contains all enabled built-in (`=y`) and modular (`=m`) options in the final Kernel configuration.")
    $Lines.Add("")

    foreach ($Category in ($KernelOptions.Category | Sort-Object -Unique)) {
        $Lines.Add("### $Category")
        $Lines.Add("")
        $Lines.Add('```text')

        foreach ($Option in ($KernelOptions | Where-Object Category -eq $Category)) {
            $Lines.Add("$($Option.Name)=$($Option.Value)")
        }

        $Lines.Add('```')
        $Lines.Add("")
    }

    $Lines.Add("## Docker Kernel Requirements")
    $Lines.Add("")
    $Lines.Add("This is a focused list of important Docker-related kernel options, not an exhaustive compatibility checklist.")
    $Lines.Add("")
    $Lines.Add("| Kernel option | Value |")
    $Lines.Add("|---|---|")

    foreach ($Key in @(
        "CONFIG_CGROUPS",
        "CONFIG_MEMCG",
        "CONFIG_CGROUP_SCHED",
        "CONFIG_CGROUP_FREEZER",
        "CONFIG_CPUSETS",
        "CONFIG_CGROUP_DEVICE",
        "CONFIG_NAMESPACES",
        "CONFIG_UTS_NS",
        "CONFIG_IPC_NS",
        "CONFIG_USER_NS",
        "CONFIG_PID_NS",
        "CONFIG_NET_NS",
        "CONFIG_SECCOMP",
        "CONFIG_SECCOMP_FILTER",
        "CONFIG_NETFILTER",
        "CONFIG_NF_NAT",
        "CONFIG_BRIDGE",
        "CONFIG_VETH",
        "CONFIG_OVERLAY_FS",
        "CONFIG_EXT4_FS"
    )) {
        $Value = Get-ConfigValue $KernelConfig $Key
        $Lines.Add("| $Key | $Value |")
    }

    $Lines.Add("")
    $Lines.Add("## Disk Image Configuration")
    $Lines.Add("")

    if ($GenimageReport.Count -gt 0) {
        foreach ($Line in $GenimageReport) {
            $Lines.Add($Line)
        }
    }
    else {
        $Lines.Add("No Genimage configuration files were found.")
    }
    $Lines.Add("")

    $Lines.Add("## Inventory Sources")
    $Lines.Add("")
    $Lines.Add("| Information | Build output source |")
    $Lines.Add("|---|---|")
    $Lines.Add("| Buildroot configuration | ``/workspace/output/.config`` |")
    $Lines.Add("| Final Kernel configuration | ``/workspace/output/build/linux-$KernelVersion/.config`` |")
    $Lines.Add("| BusyBox configuration | ``/workspace/output/build/busybox-$BusyBoxVersion/.config`` |")
    $Lines.Add("| Target package manifest | ``/workspace/output/build/packages-file-list.txt`` |")
    $Lines.Add("| Installed BusyBox applets | Target symbolic links to BusyBox |")
    $Lines.Add("| Standalone executables | Target command directories |")
    $Lines.Add("| Non-BusyBox symbolic links | Target command directories |")
    $Lines.Add("| Disk layout | Generated Genimage configuration |")
    $Lines.Add("")

    $Report = $Lines -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        $TempPath,
        $Report,
        [System.Text.UTF8Encoding]::new($false)
    )

    if (Test-Path -LiteralPath $OutputPath) {
        $BackupPath = "$OutputPath.$PID.bak"

        try {
            [System.IO.File]::Replace($TempPath, $OutputPath, $BackupPath)
        }
        finally {
            if (Test-Path -LiteralPath $BackupPath) {
                Remove-Item -LiteralPath $BackupPath -Force
            }
        }
    }
    else {
        Move-Item -LiteralPath $TempPath -Destination $OutputPath
    }

    Write-Host "System inventory generated successfully:"
    Write-Host $OutputPath
    Write-Host "Packages: $($Packages.Count)"
    Write-Host "BusyBox applets: $($BusyBoxApplets.Count)"
    Write-Host "Standalone executable files: $($StandaloneExecutables.Count)"
    Write-Host "Non-BusyBox symbolic links: $($StandaloneSymlinks.Count)"
    Write-Host "Active Kernel options: $($KernelOptions.Count)"
}
catch {
    Write-Error "System inventory generation failed: $_"
    throw
}
finally {
    if (Test-Path -LiteralPath $TempPath) {
        Remove-Item -LiteralPath $TempPath -Force
    }
}
