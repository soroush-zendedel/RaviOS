# Prepare ravios-webui image for offline seeding onto the Docker Data volume.
# Called automatically by build.ps1. Safe to run manually.
#
# Output (new convention):
#   artifacts/ravios-apps/webui/image.tar
#   artifacts/ravios-apps/webui/.prepare-stamp
#   artifacts/ravios-apps/webui/app.json  (must already exist)
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
$DestDir = Join-Path $ProjectRoot "artifacts\ravios-apps\webui"
$DestTar = Join-Path $DestDir "image.tar"
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
        return $Preferred
    }

    foreach ($candidate in $BaseImageCandidates) {
        $id = Get-ImageId $candidate
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            Write-Host "Using locally available base image: $candidate"
            return $candidate
        }
    }

    $fallback = $BaseImageCandidates[0]
    Write-Host "No preferred base image found locally - will use: $fallback"
    return $fallback
}

function Read-Stamp {
    if (-not (Test-Path -LiteralPath $StampPath)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $StampPath -Raw | ConvertFrom-Json
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
        imageId        = $ImageId
        baseId         = $BaseId
        dockerfileHash = $DockerfileHash
        resolvedBase   = $ResolvedBase
        savedAtUtc     = [DateTime]::UtcNow.ToString("o")
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $StampPath -Encoding UTF8
}

$dockerfileHash = Get-FileSha256 $Dockerfile
$imageId = Get-ImageId $ImageName
$imageExists = -not [string]::IsNullOrWhiteSpace($imageId)

$tarExists = Test-Path -LiteralPath $DestTar
$tarIsValid = $false
if ($tarExists) {
    $tarInfo = Get-Item -LiteralPath $DestTar
    $tarIsValid = ($tarInfo.Length -ge 1MB)
}

$needBuild = $Force.IsPresent
$needSave = $Force.IsPresent

if ($Force.IsPresent) {
    Write-Host "Force requested - will rebuild and save."
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
    Write-Host "Done. Tar size: $mb MB (artifacts/ravios-apps/webui/image.tar)"

    $baseId = Get-ImageId $resolvedBase
    Write-Stamp -ImageId $imageId -BaseId "$baseId" -DockerfileHash $dockerfileHash -ResolvedBase $resolvedBase
    Write-Host "Updated prepare stamp."
}
