
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = "Stop"

# Resolve project root from this script's location.
$ProjectRoot = $PSScriptRoot

if (-not (Test-Path (Join-Path $ProjectRoot ".git"))) {
    throw "Git repository not found: $ProjectRoot"
}

Write-Host ""
Write-Host "RaviOS - Line Ending Normalizer" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"
Write-Host ""

# Configure Git for LF on this repository only.
if ($PSCmdlet.ShouldProcess("Local Git configuration", "Set LF defaults")) {
    & git -C $ProjectRoot config --local core.autocrlf false
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure core.autocrlf."
    }

    & git -C $ProjectRoot config --local core.eol lf
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure core.eol."
    }
}

# Include tracked files and non-ignored untracked files.
$Files = @(
    & git -C $ProjectRoot ls-files --cached --others --exclude-standard
)

if ($LASTEXITCODE -ne 0) {
    throw "Could not retrieve the project file list from Git."
}

$Changed = 0
$AlreadyLF = 0
$Skipped = 0

foreach ($RelativePath in $Files) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        continue
    }

    $FullPath = Join-Path $ProjectRoot $RelativePath

    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        continue
    }

    $Item = Get-Item -LiteralPath $FullPath -Force

    # Do not follow symbolic links.
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $Skipped++
        continue
    }

    $Bytes = [IO.File]::ReadAllBytes($FullPath)

    # Files containing NUL bytes are treated as binary.
    if ([Array]::IndexOf([byte[]]$Bytes, [byte]0) -ge 0) {
        $Skipped++
        continue
    }

    $Stream = New-Object IO.MemoryStream
    $HasCR = $false

    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 13) {
            $HasCR = $true

            # Convert CRLF and standalone CR to LF.
            $Stream.WriteByte(10)

            if (($i + 1) -lt $Bytes.Length -and $Bytes[$i + 1] -eq 10) {
                $i++
            }
        }
        else {
            $Stream.WriteByte($Bytes[$i])
        }
    }

    if (-not $HasCR) {
        $AlreadyLF++
        $Stream.Dispose()
        continue
    }

    $NormalizedBytes = $Stream.ToArray()
    $Stream.Dispose()

    if ($PSCmdlet.ShouldProcess($RelativePath, "Normalize line endings to LF")) {
        [IO.File]::WriteAllBytes($FullPath, $NormalizedBytes)
        Write-Host "Fixed: $RelativePath" -ForegroundColor Green
        $Changed++
    }
}

Write-Host ""
Write-Host "========== Summary ==========" -ForegroundColor Cyan
Write-Host "Normalized: $Changed"
Write-Host "Already LF: $AlreadyLF"
Write-Host "Skipped:    $Skipped"
Write-Host ""

# Verify tracked files using Git's line-ending report.
Write-Host "Checking tracked files..."

$EolReport = @(
    & git -C $ProjectRoot ls-files --eol
)

if ($LASTEXITCODE -ne 0) {
    throw "Could not verify Git line endings."
}

$Problems = @(
    $EolReport | Where-Object {
        $_ -match '\bw/(crlf|mixed)\b'
    }
)

if ($Problems.Count -gt 0) {
    Write-Host "Some tracked files still have incorrect line endings:" -ForegroundColor Red
    $Problems | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host "All tracked files have LF working-tree line endings." -ForegroundColor Green
Write-Host "Normalization completed." -ForegroundColor Green
