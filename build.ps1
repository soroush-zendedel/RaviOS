[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("None", "Create")]
    [string]$DockerData = "Create",

    [string]$DiskSize = "16G",
    [string]$OutputPath = "",

    [ValidateSet("VirtualBox", "VMware")]
    [string]$Target = "VMware",

    # Remove per-build disposable image products (disk.img, docker-data.ext4, staging).
    # Does not touch Buildroot compile caches, downloads, or ccache.
    [switch]$Clean,

    # Also remove rootfs.ext2 so the next build regenerates the root filesystem image.
    [switch]$CleanRootfs,

    # Force re-application of ravios_x86_64_defconfig before building.
    [switch]$RefreshConfig
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$ProjectRoot = $PSScriptRoot
$ArtifactsDir = Join-Path $ProjectRoot "artifacts"
$VmName = "RaviOS-Dev"
$VmBaseFolder = Join-Path $ArtifactsDir "VirtualMachines"
$VmDirectory = Join-Path $VmBaseFolder $VmName
$VMwareBaseFolder = Join-Path $ArtifactsDir "VMware"
$VMwareVmFolder = Join-Path $VMwareBaseFolder $VmName

$SourceContainerPath = "/workspace/output/images/disk.img"
$BuildContainer = "ravios-dev"
$BuildrootVersionFile = Join-Path $ProjectRoot "buildroot-version.txt"
if (-not (Test-Path -LiteralPath $BuildrootVersionFile -PathType Leaf)) {
    throw "Buildroot version file was not found: $BuildrootVersionFile"
}
$BuildrootVersion = (Get-Content -LiteralPath $BuildrootVersionFile -Raw).Trim()
if ($BuildrootVersion -notmatch '^\d{4}\.\d{2}(\.\d+)?$') {
    throw "Invalid Buildroot version in buildroot-version.txt: $BuildrootVersion"
}

$BuildId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID"

$RawStageName = ".ravios-$BuildId.pending"
$RawStageHostPath = Join-Path $ArtifactsDir $RawStageName
$RawStageContainerPath = "/workspace/artifacts/$RawStageName"

# Conversion staging files stay under artifacts until the VM-specific folder is ready.
$TempVdiPath = Join-Path $VmBaseFolder ".RaviOS-Dev-$BuildId.pending.vdi"
$TempVmdkPath = Join-Path $VMwareVmFolder ".RaviOS-Dev-$BuildId.pending.vmdk"
$VMwareVmdkPath = Join-Path $VMwareVmFolder "RaviOS-Dev-$BuildId.vmdk"
$VMwareVmxPath = Join-Path $VMwareVmFolder "RaviOS-Dev-$BuildId.vmx"
$RawTempPath = $null

$VMwareExe = Join-Path $env:ProgramFiles "VMware\VMware Workstation\vmware.exe"
if (-not (Test-Path -LiteralPath $VMwareExe -PathType Leaf)) {
    $VMwareCommand = Get-Command vmware.exe -ErrorAction SilentlyContinue
    if ($VMwareCommand) {
        $VMwareExe = $VMwareCommand.Source
    }
}

$LogDirectory = Join-Path $ArtifactsDir "logs"
$LogPath = Join-Path $LogDirectory "build-$BuildId.log"
$TranscriptStarted = $false
$InventoryScriptPath = Join-Path $ProjectRoot "tools\generate-system-inventory.ps1"

# ------------------------------------------------------------
# Helper
# ------------------------------------------------------------

function Invoke-Checked {
    param(
        [string]$Program,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & $Program @Arguments
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        throw "$FailureMessage Exit code: $ExitCode"
    }
}

function Get-VersionedPath {
    param(
        [string]$Path,
        [string]$Suffix
    )

    $Directory = Split-Path -Parent $Path
    $Name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $Extension = [System.IO.Path]::GetExtension($Path)

    return Join-Path $Directory "$Name-$Suffix$Extension"
}

# Remove only artifacts that every successful build.ps1 run regenerates:
#   - Buildroot output/images/* (disk.img and related final image files)
#   - Host staging RAW / pending VDI / pending VMDK under artifacts/
# Does NOT remove:
#   - Docker volumes ravios_buildroot-src / -dl / -ccache / -output (build tree)
#   - Compiled objects under output/build, output/host, output/target, ...
#   - Offline app images under artifacts/ravios-apps/
#   - Versioned finished VMs the user may still want
function Remove-RaviOsEphemeralArtifacts {
    param(
        [string]$ContainerName = $BuildContainer,
        [string]$ArtifactsRoot = $ArtifactsDir,
        [switch]$IncludeRootfs
    )

    Write-Host ""
    Write-Host "Cleaning per-build disposable artifacts (compile cache kept)..."

    # --- Inside the Buildroot container: genimage / post-image products ---
    $containerRunning = $false
    if (-not [string]::IsNullOrWhiteSpace($ContainerName)) {
        $runningIds = @(
            & docker ps -q --filter "name=^/$ContainerName$" 2>$null |
            Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }
        )
        $containerRunning = ($runningIds.Count -gt 0)
    }

    if ($containerRunning) {
        # Always remove products that every successful image build regenerates:
        #   disk.img, docker-data.ext4, leftover seed mount dirs.
        # Optionally also remove rootfs.ext2 when -CleanRootfs was requested.
        # Keep bzImage and efi-part for incremental kernel/EFI rebuilds unless
        # the corresponding packages are invalidated by Buildroot.
        $rmList = @(
            "/workspace/output/images/disk.img",
            "/workspace/output/images/docker-data.ext4",
            "/workspace/output/images/genimage.cfg",
            "/workspace/output/images/genimage-uefi.cfg"
        )
        if ($IncludeRootfs) {
            $rmList += "/workspace/output/images/rootfs.ext2"
            $rmList += "/workspace/output/images/rootfs.ext2.gz"
            $rmList += "/workspace/output/images/rootfs.cpio"
        }

        $rmCmd = "rm -f " + ($rmList -join " ") + "; rm -rf /workspace/output/images/docker-data-mnt; mkdir -p /workspace/output/images; exit 0"
        Write-Host "  Container: removing regenerated image products..."
        if ($IncludeRootfs) {
            Write-Host "  Container: also removing rootfs.ext2 (-CleanRootfs)"
        }
        & docker exec $ContainerName sh -c $rmCmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  Could not fully clean container images (exit $LASTEXITCODE). Continuing."
        }
        else {
            Write-Host "  Container: image products removed (if they existed)."
        }
    }
    else {
        Write-Host "  Container '$ContainerName' is not running - skipped container image cleanup."
    }

    # --- Host artifacts: staging / intermediate only ---
    if (-not (Test-Path -LiteralPath $ArtifactsRoot -PathType Container)) {
        Write-Host "  Host artifacts directory missing - nothing to clean there."
        return
    }

    $removed = 0
    function Remove-HostMatch([string]$Directory, [string]$Filter) {
        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
            return
        }
        Get-ChildItem -LiteralPath $Directory -Filter $Filter -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    Write-Host "  Removed: $($_.FullName)"
                    $script:removed++
                }
                catch {
                    Write-Warning "  Could not remove $($_.FullName): $($_.Exception.Message)"
                }
            }
    }

    # Final RAW and staging under artifacts/
    $diskImg = Join-Path $ArtifactsRoot "disk.img"
    if (Test-Path -LiteralPath $diskImg -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $diskImg -Force -ErrorAction Stop
            Write-Host "  Removed: $diskImg"
            $removed++
        }
        catch {
            Write-Warning ("  Could not remove {0}: {1}" -f $diskImg, $_.Exception.Message)
        }
    }
    Remove-HostMatch $ArtifactsRoot ".ravios-*.pending"
    Remove-HostMatch $ArtifactsRoot ".*.tmp"

    # Pending conversion products
    $vmBox = Join-Path $ArtifactsRoot "VirtualMachines"
    Remove-HostMatch $vmBox ".RaviOS-Dev-*.pending.vdi"

    $vmwareDev = Join-Path $ArtifactsRoot "VMware\RaviOS-Dev"
    Remove-HostMatch $vmwareDev ".RaviOS-Dev-*.pending.vmdk"

    Write-Host "  Host intermediate files removed: $removed"
    Write-Host "Per-build cleanup finished (Buildroot ccache/dl/output tree preserved)."
}


function Invoke-SystemInventory {
    Write-Host ""
    Write-Host "Generating RaviOS system inventory..."

    try {
        if (-not (Test-Path -LiteralPath $InventoryScriptPath -PathType Leaf)) {
            throw "Inventory generator was not found: $InventoryScriptPath"
        }

        $InventoryDiskSize = if ($DockerData -eq "Create") {
            $DiskSize
        }
        else {
            "Automatic"
        }

        & $InventoryScriptPath `
            -Container $BuildContainer `
            -BuildId $BuildId `
            -DockerDataMode $DockerData `
            -DiskSize $InventoryDiskSize

        Write-Host "System inventory generation completed."
    }
    catch {
        Write-Warning "System inventory generation failed. The previous report, if any, was preserved. $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

if ($DockerData -eq "Create") {
    if ($DiskSize -notmatch '^([0-9]+)G$') {
        throw "Invalid disk size. Use values such as 4G, 16G or 32G."
    }

    $SizeGB = [int64]$Matches[1]

    if ($SizeGB -lt 3) {
        throw "Disk size must be at least 3G."
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker was not found in PATH."
}

if ($Target -eq "VirtualBox" -and -not (Get-Command VBoxManage -ErrorAction SilentlyContinue)) {
    throw "VBoxManage was not found in PATH. It is required for the VirtualBox target."
}

if ($Target -eq "VMware" -and -not (Test-Path -LiteralPath $VMwareExe -PathType Leaf)) {
    throw "VMware Workstation executable was not found. Expected: $VMwareExe"
}

# The artifacts directory is a Compose bind mount and is also the destination
# for generated images. Create it on clean checkouts before Compose is invoked.
if (-not (Test-Path -LiteralPath $ArtifactsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
}

# ------------------------------------------------------------
# Ensure the Buildroot container uses the current image and mounts
# ------------------------------------------------------------

$ComposeFile = Join-Path $ProjectRoot "docker-compose.yml"
$ExternalDescriptorHostPath = Join-Path $ProjectRoot "buildroot-external\external.desc"
$ExternalDescriptorContainerPath = "/workspace/buildroot-external/external.desc"
$DevelopmentDockerfile = Join-Path $ProjectRoot "docker\development\Dockerfile"

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "Docker Compose file was not found: $ComposeFile"
}

if (-not (Test-Path -LiteralPath $ExternalDescriptorHostPath -PathType Leaf)) {
    throw "Buildroot external tree is incomplete. Missing: $ExternalDescriptorHostPath"
}

if (-not (Test-Path -LiteralPath $DevelopmentDockerfile -PathType Leaf)) {
    throw "Development Dockerfile was not found: $DevelopmentDockerfile"
}

$ComposeVersion = & docker compose version --short 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose v2 is required to create the Buildroot container with the current project mounts."
}

# Create only missing named volumes. Existing volumes (including populated
# download/compiler caches) are never removed, cleared, or replaced.
$RequiredVolumes = @(
    "ravios_buildroot-src",
    "ravios_buildroot-output",
    "ravios_buildroot-dl",
    "ravios_buildroot-ccache"
)

foreach ($VolumeName in $RequiredVolumes) {
    $ExistingVolume = & docker volume ls --quiet --filter "name=^$VolumeName$"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not check Docker volume '$VolumeName'."
    }

    $MatchingVolumes = @($ExistingVolume | Where-Object { "$($_)".Trim() -eq $VolumeName })
    if ($MatchingVolumes.Count -eq 0) {
        Write-Host "Creating missing Docker volume: $VolumeName"
        $CreatedVolume = & docker volume create $VolumeName
        if ($LASTEXITCODE -ne 0 -or "$CreatedVolume".Trim() -ne $VolumeName) {
            throw "Could not create Docker volume '$VolumeName'."
        }
    }
    else {
        Write-Host "Reusing Docker volume: $VolumeName"
    }
}

$ComposeArguments = @(
    "--project-directory", $ProjectRoot,
    "-f", $ComposeFile
)

# Resolve the exact Compose-generated image name. Prefer a local image and
# build only when it is absent or older than the development Dockerfile.
$ComposeImages = & docker compose @ComposeArguments config --images 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Could not resolve the Buildroot image configured by Docker Compose."
}

$ComposeImage = @($ComposeImages | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -First 1)
if ($ComposeImage.Count -eq 0) {
    throw "Docker Compose did not report an image for service '$BuildContainer'."
}
$ComposeImage = "$($ComposeImage[0])".Trim()



$DockerfileWriteTime = (Get-Item -LiteralPath $DevelopmentDockerfile).LastWriteTimeUtc

# Check whether the Compose image exists without using image inspect.
# An absent image produces an empty result instead of a "No such image" error.
$ImageListOutput = & docker image ls --quiet --no-trunc --filter "reference=$ComposeImage"
$ImageListExitCode = $LASTEXITCODE

if ($ImageListExitCode -ne 0) {
    throw "Could not query local Docker images. Check that Docker Engine is running."
}

$ComposeImageId = @(
    $ImageListOutput |
    Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
    Select-Object -First 1
)

$ImageExists = ($ComposeImageId.Count -gt 0)
$ComposeImageId = if ($ImageExists) { "$($ComposeImageId[0])".Trim() } else { $null }

$ImageNeedsBuild = -not $ImageExists


if ($ImageExists) {
    $ImageCreatedText = & docker image inspect --format '{{.Created}}' $ComposeImage 2>$null

    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect creation time for local image '$ComposeImage'."
    }

    try {
        $ImageCreatedUtc = [DateTimeOffset]::Parse("$ImageCreatedText").UtcDateTime

        $ImageNeedsBuild = ($DockerfileWriteTime -gt $ImageCreatedUtc.AddSeconds(2))
    }
    catch {
        Write-Warning "Could not compare the local image timestamp with the Dockerfile; keeping the existing image to avoid an unnecessary network build."
        $ImageNeedsBuild = $false
    }
}

if ($ImageNeedsBuild) {
    Write-Host ""
    Write-Host "Building the Buildroot development image (Docker layer cache enabled)..."
    # Intentionally do not pass --no-cache or --pull. Docker's normal layer
    # cache and locally available base images remain eligible for reuse.
    Invoke-Checked docker (@("compose") + $ComposeArguments + @("build", $BuildContainer)) `
        "Could not build the Buildroot development image."
    $ComposeImageId = & docker image inspect --format '{{.Id}}' $ComposeImage
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$ComposeImageId")) {
        throw "The Buildroot development image was not available after the cached build."
    }
}



# Check container existence without inspecting a potentially missing object.
$ContainerIdOutput = & docker ps -aq --filter "name=^/$BuildContainer$"
$ContainerQueryExitCode = $LASTEXITCODE

if ($ContainerQueryExitCode -ne 0) {
    throw "Could not query Docker containers. Check Docker Engine."
}

$ContainerId = @(
    $ContainerIdOutput |
    Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
    Select-Object -First 1
)

$ContainerExists = ($ContainerId.Count -gt 0)
$ContainerRunning = ""
$ContainerImageId = $null
$ExternalMountReady = $false

if ($ContainerExists) {
    $ContainerId = "$($ContainerId[0])".Trim()

    $ContainerRunning = & docker inspect --format '{{.State.Running}}' $ContainerId
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect existing container '$BuildContainer'."
    }

    $ContainerImageId = & docker inspect --format '{{.Image}}' $ContainerId
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect image of container '$BuildContainer'."
    }

    if ("$ContainerRunning".Trim() -eq "true") {
        & docker exec $ContainerId test -f $ExternalDescriptorContainerPath
        $ExternalMountReady = ($LASTEXITCODE -eq 0)
    }
}

$ContainerNeedsRecreate = (
    -not $ContainerExists -or
    "$ContainerRunning".Trim() -ne "true" -or
    -not $ExternalMountReady -or
    "$ContainerImageId".Trim() -ne "$ComposeImageId".Trim()
)

if ($ContainerNeedsRecreate) {
    Write-Host ""
    Write-Host "Creating the Buildroot container with the existing named volumes..."

    # --no-build guarantees that Compose uses the image checked/built above.
    # No -v, volume rm, prune, or cache-clearing operation is used.
    Invoke-Checked docker (@("compose") + $ComposeArguments + @(
        "up", "-d", "--no-build", "--force-recreate", $BuildContainer
    )) "Could not recreate the Buildroot container with the current project mounts."
}
else {
    Write-Host "Buildroot container and project mounts are already current; reusing the running container."
}

$ContainerRunning = & docker inspect --format '{{.State.Running}}' $BuildContainer
if ($LASTEXITCODE -ne 0 -or "$ContainerRunning".Trim() -ne "true") {
    throw "Buildroot container '$BuildContainer' is not running after Docker Compose setup."
}

& docker exec $BuildContainer test -f $ExternalDescriptorContainerPath
if ($LASTEXITCODE -ne 0) {
    throw "The Buildroot external tree is still not mounted inside the container at /workspace/buildroot-external. Check Docker Desktop file sharing and the bind mount in docker-compose.yml."
}

# ------------------------------------------------------------
# Optional: clean only (no Buildroot make / no VM create)
# ------------------------------------------------------------
if ($Clean -or $CleanRootfs) {
    $rootfsFlag = @{ }
    if ($CleanRootfs) { $rootfsFlag["IncludeRootfs"] = $true }
    Remove-RaviOsEphemeralArtifacts -ContainerName $BuildContainer -ArtifactsRoot $ArtifactsDir @rootfsFlag
    Write-Host ""
    if ($Clean -and -not $CleanRootfs) {
        Write-Host "Clean completed (image products). No OS image was built."
    }
    elseif ($CleanRootfs -and -not $Clean) {
        Write-Host "CleanRootfs completed (including rootfs.ext2). No OS image was built."
    }
    else {
        Write-Host "Clean + CleanRootfs completed. No OS image was built."
    }
    exit 0
}

# ------------------------------------------------------------
# Initialize persistent Buildroot source and output volumes
# ------------------------------------------------------------

$BuildrootInitializerContainerPath = "/usr/local/bin/ravios-initialize-buildroot"
& docker exec $BuildContainer test -f $BuildrootInitializerContainerPath
if ($LASTEXITCODE -ne 0) {
    throw "Buildroot initializer is not mounted in the container: $BuildrootInitializerContainerPath"
}

Write-Host ""
Write-Host "Initializing or reusing persistent Buildroot source..."
Invoke-Checked docker @(
    "exec", $BuildContainer, "bash", $BuildrootInitializerContainerPath, $BuildrootVersion
) "Could not initialize Buildroot source."

# Apply or refresh Buildroot configuration from the RaviOS external defconfig.
# - First run (no .config): always apply ravios_x86_64_defconfig.
# - -RefreshConfig: force re-application so external tree changes take effect.
# - Otherwise: reuse existing .config (preserves intentional local edits).
& docker exec $BuildContainer test -s /workspace/output/.config
$OutputConfigExists = ($LASTEXITCODE -eq 0)

if ($RefreshConfig -or -not $OutputConfigExists) {
    if ($RefreshConfig) {
        Write-Host "RefreshConfig requested; re-applying ravios_x86_64_defconfig..."
    }
    else {
        Write-Host "Buildroot output configuration not found; applying RaviOS defconfig for first initialization..."
    }
    Invoke-Checked docker @(
        "exec",
        $BuildContainer,
        "make",
        "-C", "/workspace/buildroot",
        "O=/workspace/output",
        "BR2_EXTERNAL=/workspace/buildroot-external",
        "ravios_x86_64_defconfig"
    ) "Could not apply Buildroot output configuration (ravios_x86_64_defconfig)."
}
else {
    Write-Host "Existing Buildroot output configuration found; reusing it (pass -RefreshConfig to reset from defconfig)."
}

# -RefreshConfig alone: apply defconfig and stop (do not build the OS image).
if ($RefreshConfig) {
    Write-Host ""
    Write-Host "RefreshConfig completed. ravios_x86_64_defconfig has been applied."
    Write-Host "No OS image was built. Run .\build.ps1 without -RefreshConfig to build."
    exit 0
}

# ------------------------------------------------------------
# Prepare offline Chromium image artifact (copied into target rootfs by post-build.sh)
# ------------------------------------------------------------

$PrepareChromiumScript = Join-Path $ProjectRoot "docker\chromium\prepare-image.ps1"
if (Test-Path -LiteralPath $PrepareChromiumScript) {
    Write-Host ""
    Write-Host "Preparing offline Chromium Docker image..."
    # Bypass local execution policy for this helper only (unsigned project script)
    $prep = Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PrepareChromiumScript
    ) -Wait -PassThru -NoNewWindow
    if ($prep.ExitCode -ne 0) {
        throw "prepare-image.ps1 failed with exit code $($prep.ExitCode)"
    }
}
else {
    throw "prepare-image.ps1 not found. Chromium image artifact cannot be prepared."
}

# ------------------------------------------------------------
# Prepare offline Open WebUI (ravios-webui) image artifact
# ------------------------------------------------------------

$PrepareWebuiScript = Join-Path $ProjectRoot "docker\webui\prepare-image.ps1"
if (Test-Path -LiteralPath $PrepareWebuiScript) {
    Write-Host ""
    Write-Host "Preparing offline ravios-webui Docker image..."
    $prepWebui = Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PrepareWebuiScript
    ) -Wait -PassThru -NoNewWindow
    if ($prepWebui.ExitCode -ne 0) {
        throw "docker/webui/prepare-image.ps1 failed with exit code $($prepWebui.ExitCode)"
    }
}
else {
    throw "docker/webui/prepare-image.ps1 not found. WebUI image artifact cannot be prepared."
}

# ------------------------------------------------------------
# Detect existing VM
# ------------------------------------------------------------

$ExistingVM = $false

if ($Target -eq "VirtualBox") {
    $RegisteredVMs = & VBoxManage list vms

    if ($LASTEXITCODE -ne 0) {
        throw "Could not retrieve VirtualBox VM list."
    }

    $ExistingVM = [bool](
        $RegisteredVMs | Where-Object {
            $_ -match '^\s*"RaviOS-Dev"\s+\{'
        }
    )
}

$ReplaceVM = $false

if ($WhatIfPreference) {
    $PSCmdlet.ShouldProcess(
        $VmName,
        "Build image, export disk, configure and start $Target VM"
    ) | Out-Null
    return
}

if ($ExistingVM) {
    $ReplaceVM = $PSCmdlet.ShouldContinue(
        "Do you want to completely remove the existing RaviOS-Dev VM and replace it with a new one?",
        "Replace RaviOS-Dev"
    )
}

$ActionDescription = if ($ExistingVM -and -not $ReplaceVM) {
    "Build and export versioned images without modifying the existing VM"
}
elseif ($Target -eq "VMware") {
    "Build RaviOS, create VMDK and VMX, configure and start VMware Workstation VM"
}
else {
    "Build RaviOS, create VDI, configure and start VirtualBox VM"
}

if (-not $PSCmdlet.ShouldProcess($VmName, $ActionDescription)) {
    return
}

# ------------------------------------------------------------
# Resolve output paths
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $RawFinalPath = Join-Path $ArtifactsDir "disk.img"
}
elseif ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $RawFinalPath = [System.IO.Path]::GetFullPath($OutputPath)
}
else {
    # Relative custom paths are always resolved from the project root,
    # never from the caller's current working directory.
    $RawFinalPath = [System.IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot $OutputPath)
    )
}

if ($ExistingVM -and -not $ReplaceVM) {
    $RawFinalPath = Get-VersionedPath $RawFinalPath $BuildId
}
elseif (Test-Path -LiteralPath $RawFinalPath) {
    $RawFinalPath = Get-VersionedPath $RawFinalPath $BuildId
}

if (Test-Path -LiteralPath $RawFinalPath) {
    throw "RAW destination already exists; refusing to overwrite: $RawFinalPath"
}

$RawDestinationDir = Split-Path -Parent $RawFinalPath
$RawDestinationName = Split-Path -Leaf $RawFinalPath

if ([string]::IsNullOrWhiteSpace($RawDestinationName)) {
    throw "OutputPath must specify a filename."
}

if (-not (Test-Path -LiteralPath $RawDestinationDir -PathType Container)) {
    New-Item -ItemType Directory -Path $RawDestinationDir -Force | Out-Null
}

$RawTempPath = Join-Path $RawDestinationDir ".$RawDestinationName.$BuildId.tmp"
# Start build transcript
# ------------------------------------------------------------

try {
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    Start-Transcript -Path $LogPath -Force | Out-Null
    $TranscriptStarted = $true
}
catch {
    Write-Warning "Could not start build transcript: $($_.Exception.Message)"
}

# Display plan
# ------------------------------------------------------------

Write-Host ""
Write-Host "========== RaviOS Build =========="
Write-Host "Target:          $Target"
Write-Host "Docker Data:     $DockerData"
if ($DockerData -eq "Create") {
    Write-Host "Disk size:       $DiskSize"
}
else {
    Write-Host "Disk size:       Automatic"
}
Write-Host "RAW output:      $RawFinalPath"
if ($Target -eq "VirtualBox") {
    Write-Host "SSH host port:   666"
    Write-Host "SSH guest port:  666"
}
else {
    Write-Host "VMware network:  NAT (DHCP)"
}
Write-Host "Existing VM:    $ExistingVM"
Write-Host "Replace VM:     $ReplaceVM"
Write-Host "=================================="
Write-Host ""

try {

    # --------------------------------------------------------
    # Build
    # --------------------------------------------------------

    # Clear previous final image products (disk.img and siblings) and host
    # staging files. Compile caches under output/build, host, target stay intact.
    Remove-RaviOsEphemeralArtifacts -ContainerName $BuildContainer -ArtifactsRoot $ArtifactsDir

    Write-Host ""
    Write-Host "Building RaviOS..."

    $BuildArguments = @(
        "exec",
        "-e", "RAVIOS_DOCKER_DATA=$DockerData"
    )

    if ($DockerData -eq "Create") {
        $BuildArguments += @("-e", "RAVIOS_DISK_SIZE=$DiskSize")
    }

    $BuildArguments += @(
        $BuildContainer,
        "make",
        "-C", "/workspace/buildroot",
        "O=/workspace/output",
        "BR2_EXTERNAL=/workspace/buildroot-external"
    )

    Invoke-Checked docker $BuildArguments "RaviOS Buildroot build failed."

    # --------------------------------------------------------
    # Validate Buildroot image
    # --------------------------------------------------------

    Invoke-Checked docker @(
        "exec", $BuildContainer, "test", "-s", $SourceContainerPath
    ) "Build completed, but disk.img was not found."

    $SourceSizeText = & docker exec $BuildContainer stat -c %s $SourceContainerPath

    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine source image size."
    }

    $SourceSize = [int64]("$SourceSizeText".Trim())

    if ($SourceSize -lt 1) {
        throw "Source image is empty."
    }

    # --------------------------------------------------------
    # Copy RAW image to staging
    # --------------------------------------------------------

    if (Test-Path -LiteralPath $RawStageHostPath) {
        throw "Staging file already exists: $RawStageHostPath"
    }

    Write-Host ""
    Write-Host "Copying RAW image to staging..."

    Invoke-Checked docker @(
        "exec",
        $BuildContainer,
        "cp",
        "--sparse=always",
        $SourceContainerPath,
        $RawStageContainerPath
    ) "Could not copy RAW image to staging."

    if (-not (Test-Path -LiteralPath $RawStageHostPath -PathType Leaf)) {
        throw "Staging image was not found on Windows."
    }

    $StageSize = (Get-Item -LiteralPath $RawStageHostPath).Length

    if ($StageSize -ne $SourceSize) {
        throw "Staging image size does not match Buildroot image size."
    }

    # --------------------------------------------------------
    # --------------------------------------------------------
    # Export RAW image
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $RawDestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Path $RawDestinationDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $RawTempPath) {
        throw "Temporary RAW destination already exists: $RawTempPath"
    }

    $StageRoot = [System.IO.Path]::GetPathRoot($RawStageHostPath)
    $DestinationRoot = [System.IO.Path]::GetPathRoot($RawTempPath)

    if ($StageRoot -eq $DestinationRoot) {
        Move-Item -LiteralPath $RawStageHostPath -Destination $RawTempPath
    }
    else {
        Copy-Item -LiteralPath $RawStageHostPath -Destination $RawTempPath
        Remove-Item -LiteralPath $RawStageHostPath -Force
    }

    $TempRawSize = (Get-Item -LiteralPath $RawTempPath).Length

    if ($TempRawSize -ne $SourceSize) {
        throw "Temporary RAW image size verification failed."
    }

    if ($Target -eq "VirtualBox") {
        if (-not (Test-Path -LiteralPath $VmBaseFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $VmBaseFolder -Force | Out-Null
        }

        # --------------------------------------------------------
        # Convert temporary RAW to temporary VDI
        # --------------------------------------------------------

        Write-Host ""
        Write-Host "Converting RAW to dynamically allocated VDI..."

        Invoke-Checked VBoxManage @(
            "convertfromraw",
            $RawTempPath,
            $TempVdiPath,
            "--format=VDI",
            "--variant=Standard"
        ) "RAW to VDI conversion failed."

        if (-not (Test-Path -LiteralPath $TempVdiPath -PathType Leaf)) {
            throw "VDI file was not created."
        }

        if ((Get-Item -LiteralPath $TempVdiPath).Length -lt 1) {
            throw "VDI file is empty."
        }

        # --------------------------------------------------------
        # Select a unique final VDI path
        # --------------------------------------------------------

        $VdiFinalPath = Join-Path $VmDirectory "RaviOS-Dev.vdi"

        if ((Test-Path -LiteralPath $VdiFinalPath) -and -not $ReplaceVM) {
            $VdiFinalPath = Get-VersionedPath $VdiFinalPath $BuildId
        }

    }

    # --------------------------------------------------------
    # Finalize RAW image without overwriting existing files
    # --------------------------------------------------------

    Move-Item -LiteralPath $RawTempPath -Destination $RawFinalPath

    if (-not (Test-Path -LiteralPath $RawFinalPath -PathType Leaf)) {
        throw "Final RAW image was not created."
    }

    $FinalRawSize = (Get-Item -LiteralPath $RawFinalPath).Length

    if ($FinalRawSize -ne $SourceSize) {
        throw "Final RAW image size verification failed."
    }

    Write-Host "RAW image verified: $RawFinalPath"

    # --------------------------------------------------------
    # Remove Buildroot intermediate image
    # --------------------------------------------------------

    Invoke-Checked docker @(
        "exec", $BuildContainer, "rm", "-f", $SourceContainerPath
    ) "Images were exported, but Buildroot intermediate image could not be removed."

    # --------------------------------------------------------
    # VMware export and launch
    # --------------------------------------------------------

    if ($Target -eq "VMware") {
        if (-not (Test-Path -LiteralPath $VMwareVmFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $VMwareVmFolder -Force | Out-Null
        }

        Write-Host ""
        Write-Host "Converting RAW image to VMware VMDK..."

        Invoke-Checked VBoxManage @(
            "convertfromraw",
            $RawFinalPath,
            $TempVmdkPath,
            "--format=VMDK",
            "--variant=Standard"
        ) "RAW to VMDK conversion failed."

        if (-not (Test-Path -LiteralPath $TempVmdkPath -PathType Leaf)) {
            throw "VMDK file was not created."
        }
        if ((Get-Item -LiteralPath $TempVmdkPath).Length -lt 1) {
            throw "VMDK file is empty."
        }
        if ((Test-Path -LiteralPath $VMwareVmdkPath) -or (Test-Path -LiteralPath $VMwareVmxPath)) {
            throw "VMware output destination already exists; refusing to overwrite existing files."
        }

        Move-Item -LiteralPath $TempVmdkPath -Destination $VMwareVmdkPath
        $VmdkFileName = [System.IO.Path]::GetFileName($VMwareVmdkPath)

        $VmxContent = @"
.encoding = "UTF-8"
config.version = "8"
displayName = "RaviOS-Dev"
guestOS = "otherlinux-64"
virtualHW.version = "20"

memsize = "6144"
numvcpus = "2"
cpuid.coresPerSocket = "2"
firmware = "efi"
uefi.secureBoot.enabled = "FALSE"

svga.present = "TRUE"
svga.vramSize = "134217728"
mks.enable3d = "TRUE"

sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "$VmdkFileName"
sata0:0.deviceType = "disk"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "e1000"
ethernet0.startConnected = "TRUE"
ethernet0.wakeOnPcktRcv = "FALSE"

usb.present = "TRUE"
sound.present = "FALSE"
"@

        Set-Content -LiteralPath $VMwareVmxPath -Value $VmxContent -Encoding ASCII
        if (-not (Test-Path -LiteralPath $VMwareVmxPath -PathType Leaf) -or
            (Get-Item -LiteralPath $VMwareVmxPath).Length -lt 1) {
            throw "VMX configuration was not created or is empty."
        }

        Write-Host "VMware VM files are versioned; existing VMware VMs are left untouched."
        Write-Host "VMware folder: $VMwareVmFolder"
        Write-Host "VMware VMDK: $VMwareVmdkPath"
        Write-Host "VMware VMX:  $VMwareVmxPath"
        Write-Host "Network:     NAT / Intel E1000 (enabled)"

        Invoke-SystemInventory

        Write-Host "Starting RaviOS in VMware Workstation..."
        Invoke-Checked $VMwareExe @("-x", $VMwareVmxPath) `
            "Could not start RaviOS in VMware Workstation."

        # Keep only VMware artifacts (no RAW disk.img left in artifacts)
        if (Test-Path -LiteralPath $RawFinalPath) {
            Write-Host "Removing intermediate RAW image (not needed for VMware target)..."
            Remove-Item -LiteralPath $RawFinalPath -Force
        }

        Write-Host ""
        Write-Host "========== RaviOS VMware Build Completed =========="
        Write-Host "VMDK: $VMwareVmdkPath"
        Write-Host "VMX:  $VMwareVmxPath"
        Write-Host "===================================================="
        return
    }

    # Replace old VM, only after successful image preparation
    # --------------------------------------------------------

    if ($ReplaceVM) {

        Write-Host ""
        Write-Host "Inspecting existing VM..."

        $VMInfo = & VBoxManage showvminfo $VmName --machinereadable

        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect existing VM."
        }

        $StateLine = $VMInfo | Where-Object { $_ -match '^VMState=' } |
            Select-Object -First 1

        if ($StateLine -notmatch '^VMState="([^"]+)"') {
            throw "Could not determine existing VM state."
        }

        $VMState = $Matches[1]

        if ($VMState -eq "running") {
            Write-Host "Forcefully powering off existing VM..."

            Invoke-Checked VBoxManage @(
                "controlvm", $VmName, "poweroff"
            ) "Could not power off existing VM."
        }

        Write-Host "Unregistering and deleting existing RaviOS-Dev..."

        Invoke-Checked VBoxManage @(
            "unregistervm", $VmName, "--delete"
        ) "Could not delete existing RaviOS-Dev."
    }

    # --------------------------------------------------------
    # If user declined replacement, preserve existing VM
    # --------------------------------------------------------

    if ($ExistingVM -and -not $ReplaceVM) {

        Invoke-SystemInventory

        Write-Host ""
        Write-Host "Existing RaviOS-Dev was left untouched."
        Write-Host "No new VM was created."

        Write-Host ""
        Write-Host "========== Build Completed =========="
        Write-Host "====================================="

        return
    }

    # --------------------------------------------------------
    # Create new VM
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $VmBaseFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $VmBaseFolder -Force | Out-Null
    }

    Write-Host ""
    Write-Host "Creating VirtualBox VM..."

    Invoke-Checked VBoxManage @(
        "createvm",
        "--name", $VmName,
        "--basefolder", $VmBaseFolder,
        "--ostype", "Linux_64",
        "--register"
    ) "Could not create RaviOS-Dev VM."

    # VirtualBox creates the VM directory as part of createvm.
    # Place the disk inside that directory only after it exists.
    if (-not (Test-Path -LiteralPath $VmDirectory -PathType Container)) {
        throw "VirtualBox VM directory was not created: $VmDirectory"
    }

    # Preserve unrelated files if an old VM directory was not fully removed.
    if (Test-Path -LiteralPath $VdiFinalPath) {
        $VdiFinalPath = Get-VersionedPath $VdiFinalPath $BuildId
    }

    Move-Item -LiteralPath $TempVdiPath -Destination $VdiFinalPath

    if (-not (Test-Path -LiteralPath $VdiFinalPath -PathType Leaf)) {
        throw "Final VDI file was not created."
    }

    if ((Get-Item -LiteralPath $VdiFinalPath).Length -lt 1) {
        throw "Final VDI file is empty."
    }

    Invoke-Checked VBoxManage @(
        "showmediuminfo", "disk", $VdiFinalPath
    ) "Final VDI verification failed."

    Write-Host "VDI verified: $VdiFinalPath"

    # --------------------------------------------------------
    # Configure VM hardware and network
    # --------------------------------------------------------

    Write-Host "Configuring VM hardware..."

    Invoke-Checked VBoxManage @(
        "modifyvm", $VmName,
        "--memory", "6144",
        "--cpus", "2",
        "--firmware", "efi",
        "--boot1", "disk",
        "--graphicscontroller", "vmsvga",
        "--vram", "16",
        "--nic1", "nat",
        "--nic-type1", "82540EM",
        "--cable-connected1", "on",
        "--natpf1", "ssh,tcp,127.0.0.1,666,,666",
        "--audio-enabled", "off"
    ) "Could not configure VM hardware."

    # --------------------------------------------------------
    # Create SATA controller and attach VDI
    # --------------------------------------------------------

    Write-Host "Creating SATA controller..."

    Invoke-Checked VBoxManage @(
        "storagectl", $VmName,
        "--name", "SATA Controller",
        "--add", "sata",
        "--controller", "IntelAhci"
    ) "Could not create SATA controller."

    Write-Host "Attaching VDI..."

    Invoke-Checked VBoxManage @(
        "storageattach", $VmName,
        "--storagectl", "SATA Controller",
        "--port", "0",
        "--device", "0",
        "--type", "hdd",
        "--medium", $VdiFinalPath
    ) "Could not attach VDI to VM."

    # --------------------------------------------------------
    # Start VM
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Starting RaviOS-Dev..."

    Invoke-Checked VBoxManage @(
        "startvm", $VmName, "--type", "gui"
    ) "Could not start RaviOS-Dev."

    Invoke-SystemInventory

    # Keep only VirtualBox artifacts (no RAW disk.img left in artifacts)
    if (Test-Path -LiteralPath $RawFinalPath) {
        Write-Host "Removing intermediate RAW image (not needed for VirtualBox target)..."
        Remove-Item -LiteralPath $RawFinalPath -Force
    }

    Write-Host ""
    Write-Host "========== RaviOS Build Completed =========="
    Write-Host "VDI image: $VdiFinalPath"
    Write-Host "VM:        $VmName"
    Write-Host "VM folder: $VmBaseFolder\$VmName"
    Write-Host "SSH:       ssh root@127.0.0.1 -p 666"
    Write-Host "============================================="

}
finally {

    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-Warning "Could not stop build transcript: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $RawStageHostPath) {
        Remove-Item -LiteralPath $RawStageHostPath -Force
    }

    if ($RawTempPath -and (Test-Path -LiteralPath $RawTempPath)) {
        Remove-Item -LiteralPath $RawTempPath -Force
    }

    if (Test-Path -LiteralPath $TempVdiPath) {
        Remove-Item -LiteralPath $TempVdiPath -Force
    }

    if (Test-Path -LiteralPath $TempVmdkPath) {
        Remove-Item -LiteralPath $TempVmdkPath -Force
    }
}
