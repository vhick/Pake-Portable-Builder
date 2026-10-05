param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$KitRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$BuiltExe,
    [Parameter(Mandatory=$true)][string]$AppName,
    [Parameter(Mandatory=$true)][string]$Url
)

$ErrorActionPreference = "Stop"

function Safe-Name([string]$Name) {
    $safe = $Name -replace '[\\/:*?"<>|]','-'
    $safe = $safe.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "PakeApp" }
    return $safe
}

$safeName = Safe-Name $AppName
$appOut = Join-Path $OutputRoot $safeName

if (Test-Path -LiteralPath $appOut) {
    Remove-Item -LiteralPath $appOut -Recurse -Force
}

New-Item -ItemType Directory -Path $appOut -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $appOut "Data") -Force | Out-Null

$portableExeName = "$safeName-Portable.exe"
Copy-Item -LiteralPath $BuiltExe -Destination (Join-Path $appOut $portableExeName) -Force

$tauriConfig = Join-Path $SourceRoot "src-tauri\.pake\tauri.conf.json"
$productName = $AppName
$identifier = ""

if (Test-Path -LiteralPath $tauriConfig -PathType Leaf) {
    try {
        $cfg = Get-Content -LiteralPath $tauriConfig -Raw | ConvertFrom-Json
        if ($cfg.productName) { $productName = [string]$cfg.productName }
        if ($cfg.identifier) { $identifier = [string]$cfg.identifier }
    } catch {
        Write-Host "Could not parse generated tauri.conf.json: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$templates = @(
    "LAUNCH-PAKE-PORTABLE.cmd",
    "INSTALL-PORTABLE-STARTUP.cmd",
    "REMOVE-PORTABLE-STARTUP.cmd",
    "VERIFY-PORTABLE.ps1",
    "MIGRATE-OLD-DATA.ps1",
    "CLEAN-OLD-HOST-DATA.ps1"
)

foreach ($template in $templates) {
    $source = Join-Path $KitRoot "portable\$template"
    $destination = Join-Path $appOut $template
    $content = Get-Content -LiteralPath $source -Raw

    $content = $content.Replace("__APP_NAME__", $safeName)
    $content = $content.Replace("__APP_NAME_PS__", $safeName.Replace("'","''"))
    $content = $content.Replace("__PRODUCT_NAME_PS__", $productName.Replace("'","''"))
    $content = $content.Replace("__IDENTIFIER_PS__", $identifier.Replace("'","''"))
    $content = $content.Replace("__APP_EXE__", $portableExeName)

    Set-Content -LiteralPath $destination -Value $content -Encoding UTF8
}

$patchMarker = Join-Path $SourceRoot ".pake-true-portable-patch.json"
if (-not (Test-Path -LiteralPath $patchMarker -PathType Leaf)) {
    throw "True-portable patch marker is missing."
}

Copy-Item -LiteralPath $patchMarker `
    -Destination (Join-Path $appOut "TRUE-PORTABLE-PATCH.json") `
    -Force

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    app_name = $AppName
    product_name = $productName
    identifier = $identifier
    url = $Url
    executable = $portableExeName
    upstream_revision = $revision
    data = @{
        tauri_plugins = "./Data/App"
        webview = "./Data/WebView/$productName"
    }
    downloads = "normal Windows Downloads directory"
    build_method = "Pake CLI --keep-binary"
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $appOut "PORTABLE-BUILD.json") -Encoding UTF8

Set-Content -LiteralPath (Join-Path $appOut "SOURCE-REVISION.txt") `
    -Encoding UTF8 `
    -Value @(
        "Upstream: https://github.com/tw93/Pake",
        "Revision: $revision",
        "Website: $Url",
        "App name: $AppName",
        "Generated: $(Get-Date)"
    )

foreach ($pair in @(
    @{ Source=(Join-Path $SourceRoot "LICENSE"); Destination="LICENSE-UPSTREAM.txt" },
    @{ Source=(Join-Path $SourceRoot "LICENSE-EXCEPTION"); Destination="LICENSE-EXCEPTION-UPSTREAM.txt" },
    @{ Source=(Join-Path $SourceRoot "TRADEMARK.md"); Destination="TRADEMARK-UPSTREAM.txt" }
)) {
    if (Test-Path -LiteralPath $pair.Source -PathType Leaf) {
        Copy-Item -LiteralPath $pair.Source `
            -Destination (Join-Path $appOut $pair.Destination) `
            -Force
    }
}

Write-Host "Portable package assembled:" -ForegroundColor Green
Write-Host "  $appOut"
