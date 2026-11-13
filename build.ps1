[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("None", "Create")]
    [string]$DockerData = "Create",

    [string]$DiskSize = "16G",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$ProjectRoot = $PSScriptRoot
$ArtifactsDir = Join-Path $ProjectRoot "artifacts"
$VmName = "RaviOS-Dev"
$VmBaseFolder = Join-Path $ArtifactsDir "VirtualMachines"

$SourceContainerPath = "/workspace/output/images/disk.img"
$BuildContainer = "ravios-dev"

$BuildId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID"

$RawStageName = ".ravios-$BuildId.pending"
$RawStageHostPath = Join-Path $ArtifactsDir $RawStageName
$RawStageContainerPath = "/workspace/artifacts/$RawStageName"

$TempVdiPath = Join-Path $ArtifactsDir ".RaviOS-Dev-$BuildId.pending.vdi"
$RawTempPath = $null

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

if (-not (Get-Command VBoxManage -ErrorAction SilentlyContinue)) {
    throw "VBoxManage was not found in PATH."
}

if (-not (Test-Path -LiteralPath $ArtifactsDir -PathType Container)) {
    throw "Artifacts directory does not exist: $ArtifactsDir"
}

$ContainerRunning = & docker inspect --format '{{.State.Running}}' $BuildContainer

if ($LASTEXITCODE -ne 0 -or "$ContainerRunning".Trim() -ne "true") {
    throw "Buildroot container '$BuildContainer' is not running."
}

# ------------------------------------------------------------
# Detect existing VM
# ------------------------------------------------------------

$RegisteredVMs = & VBoxManage list vms

if ($LASTEXITCODE -ne 0) {
    throw "Could not retrieve VirtualBox VM list."
}

$ExistingVM = [bool](
    $RegisteredVMs | Where-Object {
        $_ -match '^\s*"RaviOS-Dev"\s+\{'
    }
)

$ReplaceVM = $false

if ($WhatIfPreference) {
    $PSCmdlet.ShouldProcess(
        $VmName,
        "Build image, create VDI, configure and start VirtualBox VM"
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
else {
    "Build RaviOS, create VDI, configure and start the VM"
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
else {
    $RawFinalPath = [System.IO.Path]::GetFullPath($OutputPath)
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

$RawTempPath = Join-Path $RawDestinationDir ".$RawDestinationName.$BuildId.tmp"
# Display plan
# ------------------------------------------------------------

Write-Host ""
Write-Host "========== RaviOS Build =========="
Write-Host "Docker Data:     $DockerData"
if ($DockerData -eq "Create") {
    Write-Host "Disk size:       $DiskSize"
}
else {
    Write-Host "Disk size:       Automatic"
}
Write-Host "RAW output:      $RawFinalPath"
Write-Host "SSH host port:   666"
Write-Host "SSH guest port:  666"
Write-Host "Existing VM:    $ExistingVM"
Write-Host "Replace VM:     $ReplaceVM"
Write-Host "=================================="
Write-Host ""

try {

    # --------------------------------------------------------
    # Build
    # --------------------------------------------------------

    Write-Host "Removing previous Buildroot image..."

    Invoke-Checked docker @(
        "exec", $BuildContainer, "rm", "-f", $SourceContainerPath
    ) "Could not remove the previous Buildroot image."

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

    $VdiFinalPath = Join-Path $ArtifactsDir "RaviOS-Dev.vdi"

    if (Test-Path -LiteralPath $VdiFinalPath) {
        $VdiFinalPath = Get-VersionedPath $VdiFinalPath $BuildId
    }

    if (Test-Path -LiteralPath $VdiFinalPath) {
        throw "VDI destination already exists; refusing to overwrite: $VdiFinalPath"
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
    # Finalize and verify VDI
    # --------------------------------------------------------

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
    # Remove Buildroot intermediate image
    # --------------------------------------------------------

    Invoke-Checked docker @(
        "exec", $BuildContainer, "rm", "-f", $SourceContainerPath
    ) "Images were exported, but Buildroot intermediate image could not be removed."
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

        Write-Host ""
        Write-Host "Existing RaviOS-Dev was left untouched."
        Write-Host "No new VM was created."

        Write-Host ""
        Write-Host "========== Build Completed =========="
        Write-Host "RAW: $RawFinalPath"
        Write-Host "VDI: $VdiFinalPath"
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

    # --------------------------------------------------------
    # Configure VM hardware and network
    # --------------------------------------------------------

    Write-Host "Configuring VM hardware..."

    Invoke-Checked VBoxManage @(
        "modifyvm", $VmName,
        "--memory", "2048",
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

    Write-Host ""
    Write-Host "========== RaviOS Build Completed =========="
    Write-Host "RAW image: $RawFinalPath"
    Write-Host "VDI image: $VdiFinalPath"
    Write-Host "VM:        $VmName"
    Write-Host "VM folder: $VmBaseFolder\$VmName"
    Write-Host "SSH:       ssh root@127.0.0.1 -p 666"
    Write-Host "============================================="

}
finally {

    if (Test-Path -LiteralPath $RawStageHostPath) {
        Remove-Item -LiteralPath $RawStageHostPath -Force
    }

    if ($RawTempPath -and (Test-Path -LiteralPath $RawTempPath)) {
        Remove-Item -LiteralPath $RawTempPath -Force
    }

    if (Test-Path -LiteralPath $TempVdiPath) {
        Remove-Item -LiteralPath $TempVdiPath -Force
    }
}
