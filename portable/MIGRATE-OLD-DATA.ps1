$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$productName = '__PRODUCT_NAME_PS__'
$identifier = '__IDENTIFIER_PS__'

$webTarget = Join-Path (Join-Path $root "Data\WebView") $productName
$appTarget = Join-Path $root "Data\App"
$backupRoot = Join-Path $root "MigrationBackups"

New-Item -ItemType Directory -Path $webTarget,$appTarget,$backupRoot -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Copy-WithBackup {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$BackupName
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "Not found: $Source" -ForegroundColor DarkGray
        return
    }

    $backup = Join-Path $backupRoot "$BackupName-$stamp"
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    Write-Host "Backing up:"
    Write-Host "  $Source"
    & robocopy.exe "$Source" "$backup" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Backup failed: $Source" }

    Write-Host "Migrating to:"
    Write-Host "  $Destination"
    & robocopy.exe "$Source" "$Destination" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Migration failed: $Source" }
}

Write-Host ""
Write-Host "Pake app data migration" -ForegroundColor Cyan
Write-Host ""

# Pake's historical explicit WebView profile path on Windows.
Copy-WithBackup `
    -Source (Join-Path $env:APPDATA $productName) `
    -Destination $webTarget `
    -BackupName "WebView"

# Tauri/plugin paths that may exist from a non-portable build.
if ($identifier) {
    Copy-WithBackup `
        -Source (Join-Path $env:APPDATA $identifier) `
        -Destination $appTarget `
        -BackupName "Tauri-Roaming"

    Copy-WithBackup `
        -Source (Join-Path $env:LOCALAPPDATA $identifier) `
        -Destination $appTarget `
        -BackupName "Tauri-Local"
}

Write-Host ""
Write-Host "Migration finished." -ForegroundColor Green
Write-Host "Nothing was deleted from AppData."
Write-Host "Test the portable app first, then optionally use CLEAN-OLD-HOST-DATA.ps1."
Read-Host "Press Enter to close" | Out-Null
