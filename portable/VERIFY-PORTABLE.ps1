$ErrorActionPreference = "Continue"

$root = $PSScriptRoot
$appName = '__APP_NAME_PS__'
$productName = '__PRODUCT_NAME_PS__'
$identifier = '__IDENTIFIER_PS__'

$reportDir = Join-Path $root "Verification"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report = Join-Path $reportDir ("Verify-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function W([string]$Text="") {
    Add-Content -LiteralPath $report -Value $Text -Encoding UTF8
}

W "PAKE TRUE-PORTABLE VERIFICATION"
W ("Generated: {0}" -f (Get-Date))
W ("App: {0}" -f $appName)
W ("Product name: {0}" -f $productName)
W ("Identifier: {0}" -f $identifier)
W ("Portable folder: {0}" -f $root)
W ""

$exe = Join-Path $root "__APP_EXE__"
$appData = Join-Path $root "Data\App"
$webView = Join-Path (Join-Path $root "Data\WebView") $productName

W ("EXE exists: {0}" -f (Test-Path -LiteralPath $exe -PathType Leaf))
W ("Data\App exists: {0}" -f (Test-Path -LiteralPath $appData -PathType Container))
W ("WebView data exists: {0}" -f (Test-Path -LiteralPath $webView -PathType Container))

W ""
W "=== Portable Data contents ==="
Get-ChildItem -LiteralPath (Join-Path $root "Data") -Force -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 500 |
    ForEach-Object { W $_.FullName }

W ""
W "=== Known old host locations ==="
$old = @(
    (Join-Path $env:APPDATA $productName)
)

if ($identifier) {
    $old += (Join-Path $env:APPDATA $identifier)
    $old += (Join-Path $env:LOCALAPPDATA $identifier)
}

foreach ($p in $old | Select-Object -Unique) {
    W ("{0}: {1}" -f $p,(Test-Path -LiteralPath $p))
}

W ""
W "Downloads intentionally remain in the normal Windows Downloads folder."
W "This verifier does not print cookies, Local Storage, IndexedDB, or website content."

Write-Host ""
Write-Host "Verification report:" -ForegroundColor Cyan
Write-Host "  $report"
