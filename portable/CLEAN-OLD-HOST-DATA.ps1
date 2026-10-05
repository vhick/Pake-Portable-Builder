$ErrorActionPreference = "Stop"

$productName = '__PRODUCT_NAME_PS__'
$identifier = '__IDENTIFIER_PS__'

$targets = @(
    (Join-Path $env:APPDATA $productName)
)

if ($identifier) {
    $targets += (Join-Path $env:APPDATA $identifier)
    $targets += (Join-Path $env:LOCALAPPDATA $identifier)
}

$existing = @($targets | Select-Object -Unique | Where-Object {
    Test-Path -LiteralPath $_ -PathType Container
})

Write-Host ""
Write-Host "Remove old non-portable Pake app data" -ForegroundColor Cyan
Write-Host ""

if ($existing.Count -eq 0) {
    Write-Host "No known old AppData folders were found."
    exit 0
}

Write-Host "The following folders will be deleted:" -ForegroundColor Yellow
$existing | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Only continue after the portable app has been tested."
$answer = Read-Host "Type DELETE to continue"

if ($answer -cne "DELETE") {
    Write-Host "Cancelled."
    exit 0
}

foreach ($path in $existing) {
    Remove-Item -LiteralPath $path -Recurse -Force
    Write-Host "Removed: $path" -ForegroundColor Green
}

Read-Host "Press Enter to close" | Out-Null
