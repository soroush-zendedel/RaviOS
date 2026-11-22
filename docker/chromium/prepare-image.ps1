# Prepare ravios-chromium image for offline inclusion in RaviOS rootfs.
# Called automatically by build.ps1. Safe to run manually.

[CmdletBinding()]
param(
    [string]$ImageName = "ravios-chromium:latest",
    [string]$BaseImage = "docker.arvancloud.ir/library/debian:bookworm-slim",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Dockerfile = Join-Path $ProjectRoot "docker\chromium\Dockerfile"
$DestDir = Join-Path $ProjectRoot "artifacts\ravios-chromium\image"
$DestTar = Join-Path $DestDir "ravios-chromium.tar"

if (-not (Test-Path -LiteralPath $Dockerfile)) {
    throw "Dockerfile not found: $Dockerfile"
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

$needBuild = $Force.IsPresent
$needSave = $Force.IsPresent

$tarExists = Test-Path -LiteralPath $DestTar
$tarIsValid = $false
if ($tarExists) {
    $tarInfo = Get-Item -LiteralPath $DestTar
    $tarIsValid = ($tarInfo.Length -ge 1MB)
    if (-not $tarIsValid) {
        Write-Host "Chromium image tar is too small - will recreate."
    }
}
else {
    Write-Host "Chromium image tar not found - will create it."
}


# Do not trust an existing tar blindly: the image or Dockerfile may have
# changed since the archive was generated.

$imageIds = @(
    & docker image ls --quiet --no-trunc --filter "reference=$ImageName" |
    Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }
)

if ($LASTEXITCODE -ne 0) {
    throw "Could not query local Docker images."
}

$imageExists = ($imageIds.Count -gt 0)

if (-not $imageExists) {
    Write-Host "Docker image $ImageName not found - will build it."
    $needBuild = $true
    $needSave = $true
}
else {
    $imageCreatedText = & docker image inspect --format '{{.Created}}' $ImageName

    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect existing Docker image '$ImageName'."
    }

    try {
        $imageCreatedUtc = [DateTimeOffset]::Parse("$imageCreatedText").UtcDateTime
        $dockerfileWriteTime = (Get-Item -LiteralPath $Dockerfile).LastWriteTimeUtc

        if ($dockerfileWriteTime -gt $imageCreatedUtc.AddSeconds(2)) {
            Write-Host "Dockerfile is newer than the local image - rebuilding."
            $needBuild = $true
            $needSave = $true
        }

        if (-not $tarIsValid) {
            $needSave = $true
        }
        elseif ((Get-Item -LiteralPath $DestTar).LastWriteTimeUtc -lt $imageCreatedUtc) {
            Write-Host "Saved archive is older than the local image - refreshing it."
            $needSave = $true
        }
    }
    catch {
        Write-Warning "Could not compare image, Dockerfile, and archive timestamps; rebuilding the image archive."
        $needBuild = $true
        $needSave = $true
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
}
