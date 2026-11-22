[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ComposeFile = Join-Path $ProjectRoot "docker-compose.yml"
$PreserveVolume = "ravios_buildroot-dl"
$ResetVolumes = @(
    "ravios_buildroot-src",
    "ravios_buildroot-output",
    "ravios_buildroot-ccache"
)

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker was not found in PATH."
}
if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "docker-compose.yml was not found: $ComposeFile"
}

Write-Host "This migration will DELETE and recreate only these Docker volumes:"
$ResetVolumes | ForEach-Object { Write-Host "  - $_" }
Write-Host "The following volume will be preserved: $PreserveVolume"
Write-Host "No other Docker volumes, images, or artifacts will be removed."

$answer = Read-Host "Type RESET-RAVIOS-BUILDROOT to continue"
if ($answer -cne "RESET-RAVIOS-BUILDROOT") {
    Write-Host "Cancelled. No volumes were changed."
    exit 0
}

# Ensure the download cache exists before any destructive operation.
$dl = @(& docker volume ls --quiet --filter "name=^$PreserveVolume$")
if ($LASTEXITCODE -ne 0) { throw "Could not inspect Docker volumes." }
if (@($dl | Where-Object { "$($_)".Trim() -eq $PreserveVolume }).Count -ne 1) {
    throw "Preserved download volume '$PreserveVolume' does not exist. Refusing to continue."
}

# Stop/remove only this Compose project container. 'down' without -v preserves all volumes.
& docker compose --project-directory $ProjectRoot -f $ComposeFile down
if ($LASTEXITCODE -ne 0) { throw "Could not stop the RaviOS Compose service. No volumes were removed." }

foreach ($name in $ResetVolumes) {
    $found = @(& docker volume ls --quiet --filter "name=^$name$")
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect volume '$name'." }
    if (@($found | Where-Object { "$($_)".Trim() -eq $name }).Count -gt 0) {
        Write-Host "Removing $name ..."
        & docker volume rm $name
        if ($LASTEXITCODE -ne 0) { throw "Could not remove '$name'. The download volume remains untouched." }
    }
}

foreach ($name in $ResetVolumes) {
    Write-Host "Creating empty volume $name ..."
    $created = & docker volume create $name
    if ($LASTEXITCODE -ne 0 -or "$created".Trim() -ne $name) {
        throw "Could not create empty volume '$name'."
    }
}

# Verify the protected volume still exists.
$dlAfter = @(& docker volume ls --quiet --filter "name=^$PreserveVolume$")
if ($LASTEXITCODE -ne 0 -or @($dlAfter | Where-Object { "$($_)".Trim() -eq $PreserveVolume }).Count -ne 1) {
    throw "Verification failed: preserved download volume is not visible. Do not run the build until investigated."
}

Write-Host ""
Write-Host "RaviOS Buildroot volumes have been reset. '$PreserveVolume' was preserved."
Write-Host "Next: run .\build.ps1 with your normal build arguments."
