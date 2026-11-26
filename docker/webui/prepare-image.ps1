# Prepare ravios-webui image for offline inclusion in RaviOS rootfs.
# Called automatically by build.ps1. Safe to run manually.
#
# Builds/tags ravios-webui:latest from the official Open WebUI image and
# exports artifacts/ravios-webui/image/ravios-webui-image.tar.
#
# Rebuild policy (avoids false rebuilds from Dockerfile mtime after unzip/copy):
#   - Force switch              -> always rebuild + save
#   - Image missing             -> build + save
#   - Dockerfile content change -> rebuild + save
#   - Image present, no stamp   -> save only + write stamp (no rebuild)
#   - Tar missing/too small     -> save only
#   - Otherwise                 -> skip (already up to date)
#
# Base image resolution (first match that exists locally, else first for pull):
#   openwebui/open-webui:latest
#   registry.docker.ir/openwebui/open-webui:latest
#   docker.arvancloud.ir/openwebui/open-webui:latest
#   ghcr.io/open-webui/open-webui:main

[CmdletBinding()]
param(
    [string]$ImageName = "ravios-webui:latest",
    [string]$BaseImage = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Dockerfile = Join-Path $ProjectRoot "docker\webui\Dockerfile"
$DestDir = Join-Path $ProjectRoot "artifacts\ravios-webui\image"
$DestTar = Join-Path $DestDir "ravios-webui-image.tar"
$StampPath = Join-Path $DestDir ".prepare-stamp"

$BaseImageCandidates = @(
    "openwebui/open-webui:latest",
    "registry.docker.ir/openwebui/open-webui:latest",
    "docker.arvancloud.ir/openwebui/open-webui:latest",
    "ghcr.io/open-webui/open-webui:main"
)

if (-not (Test-Path -LiteralPath $Dockerfile)) {
    throw "Dockerfile not found: $Dockerfile"
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ImageId([string]$Name) {
    # Missing images must not become terminating errors under $ErrorActionPreference=Stop.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $id = & docker image inspect --format '{{.Id}}' $Name 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$id")) {
            return $null
        }
        return "$id".Trim()
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}

function Resolve-BaseImageName {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        return $Preferred.Trim()
    }

    foreach ($candidate in $BaseImageCandidates) {
        if (-not [string]::IsNullOrWhiteSpace((Get-ImageId $candidate))) {
            Write-Host "Using local base image: $candidate"
            return $candidate
        }
    }

    # None present locally — docker build will pull the primary name.
    Write-Host "No local Open WebUI base image found; will use $($BaseImageCandidates[0]) for build/pull."
    return $BaseImageCandidates[0]
}

function Read-Stamp {
    if (-not (Test-Path -LiteralPath $StampPath)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $StampPath -Raw -ErrorAction Stop |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-Stamp {
    param(
        [string]$ImageId,
        [string]$BaseId,
        [string]$DockerfileHash,
        [string]$ResolvedBase
    )
    $obj = [ordered]@{
        imageId         = $ImageId
        baseImageId     = $BaseId
        dockerfileHash  = $DockerfileHash
        imageName       = $ImageName
        baseImage       = $ResolvedBase
        savedAtUtc      = [DateTime]::UtcNow.ToString("o")
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $StampPath -Encoding UTF8
}

$dockerfileHash = Get-FileSha256 $Dockerfile
$tarExists = Test-Path -LiteralPath $DestTar
$tarIsValid = $false
if ($tarExists) {
    $tarInfo = Get-Item -LiteralPath $DestTar
    $tarIsValid = ($tarInfo.Length -ge 100MB)
    if (-not $tarIsValid) {
        Write-Host "WebUI image tar is too small ($([math]::Round($tarInfo.Length/1MB,1)) MB) - will recreate."
    }
}
else {
    Write-Host "WebUI image tar not found - will create it."
}

$imageId = Get-ImageId $ImageName
$imageExists = -not [string]::IsNullOrWhiteSpace($imageId)

$needBuild = $Force.IsPresent
$needSave = $Force.IsPresent

if ($Force.IsPresent) {
    Write-Host "Force specified - will rebuild and save."
}
elseif (-not $imageExists) {
    Write-Host "Docker image $ImageName not found - will build it."
    $needBuild = $true
    $needSave = $true
}
else {
    $stamp = Read-Stamp
    $dockerfileChanged = $false
    if ($null -ne $stamp -and -not [string]::IsNullOrWhiteSpace("$($stamp.dockerfileHash)")) {
        $dockerfileChanged = ("$($stamp.dockerfileHash)" -ne "$dockerfileHash")
    }

    if ($dockerfileChanged) {
        Write-Host "Dockerfile content changed since last prepare - will rebuild."
        $needBuild = $true
        $needSave = $true
    }
    elseif ($null -eq $stamp) {
        # Image already present (e.g. tagged manually) but no stamp yet:
        # do not rebuild; just export tar and write stamp.
        Write-Host "Image exists without prepare stamp - will save archive only."
        $needSave = $true
    }
    elseif (-not $tarIsValid) {
        Write-Host "Image and stamp OK but tar missing/invalid - will save only."
        $needSave = $true
    }
    elseif ("$($stamp.imageId)" -ne "$imageId") {
        Write-Host "Local image id differs from stamp - will save only."
        $needSave = $true
    }
    else {
        Write-Host "ravios-webui image archive is already up to date."
        return
    }
}

$resolvedBase = Resolve-BaseImageName -Preferred $BaseImage

if ($needSave) {

    if ($needBuild) {
        Write-Host "Building $ImageName from $resolvedBase ..."
        docker build -t $ImageName `
            --build-arg "BASE_IMAGE=$resolvedBase" `
            -f $Dockerfile `
            (Join-Path $ProjectRoot "docker\webui")
        if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

        $imageId = Get-ImageId $ImageName
        if ([string]::IsNullOrWhiteSpace($imageId)) {
            throw "Built image '$ImageName' but could not read its Id."
        }
    }
    else {
        Write-Host "Docker image $ImageName already exists - will save only."
    }

    Write-Host "Saving to $DestTar ..."
    if (Test-Path -LiteralPath $DestTar) {
        Remove-Item -LiteralPath $DestTar -Force
    }
    docker save $ImageName -o $DestTar
    if ($LASTEXITCODE -ne 0) { throw "docker save failed" }

    $mb = [math]::Round((Get-Item -LiteralPath $DestTar).Length / 1MB, 1)
    Write-Host "Done. Tar size: $mb MB"

    $baseId = Get-ImageId $resolvedBase
    Write-Stamp -ImageId $imageId -BaseId "$baseId" -DockerfileHash $dockerfileHash -ResolvedBase $resolvedBase
    Write-Host "Updated prepare stamp."
}
