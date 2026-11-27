# Prepare ravios-chromium image for offline seeding onto the Docker Data volume.
# Called automatically by build.ps1. Safe to run manually.
#
# Output (new convention):
#   artifacts/ravios-apps/chromium/image.tar
#   artifacts/ravios-apps/chromium/.prepare-stamp
#   artifacts/ravios-apps/chromium/app.json  (must already exist)
#
# Rebuild policy (same idea as webui; avoids false rebuilds from Dockerfile mtime
# after unzip/copy):
#   - Force switch              -> always rebuild + save
#   - Image missing             -> build + save
#   - Dockerfile content change -> rebuild + save
#   - Image present, no stamp   -> save only + write stamp (no rebuild)
#   - Tar missing/too small     -> save only
#   - Image id differs stamp    -> save only
#   - Otherwise                 -> skip (already up to date)

[CmdletBinding()]
param(
    [string]$ImageName = "ravios-chromium:latest",
    [string]$BaseImage = "docker.arvancloud.ir/library/debian:bookworm-slim",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Dockerfile = Join-Path $ProjectRoot "docker\chromium\Dockerfile"
$DestDir = Join-Path $ProjectRoot "artifacts\ravios-apps\chromium"
$DestTar = Join-Path $DestDir "image.tar"
$StampPath = Join-Path $DestDir ".prepare-stamp"

if (-not (Test-Path -LiteralPath $Dockerfile)) {
    throw "Dockerfile not found: $Dockerfile"
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ImageId([string]$Name) {
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
        [string]$DockerfileHash,
        [string]$BaseImageName
    )
    $obj = [ordered]@{
        imageId        = $ImageId
        dockerfileHash = $DockerfileHash
        baseImage      = $BaseImageName
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
        # Image already present but no stamp yet (first run after this policy change,
        # or manual docker build): export tar once and write stamp.
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
        Write-Host "ravios-chromium image archive is already up to date."
        return
    }
}

if ($needSave) {

    if ($needBuild) {
        Write-Host "Building $ImageName ..."
        docker build -t $ImageName `
            --build-arg "BASE_IMAGE=$BaseImage" `
            -f $Dockerfile `
            (Join-Path $ProjectRoot "docker\chromium")
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
    Write-Host "Done. Tar size: $mb MB (artifacts/ravios-apps/chromium/image.tar)"

    Write-Stamp -ImageId $imageId -DockerfileHash $dockerfileHash -BaseImageName $BaseImage
    Write-Host "Updated prepare stamp."
}
