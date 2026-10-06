param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"

$utilFile = Join-Path $SourceRoot "src-tauri\src\util.rs"
$libFile = Join-Path $SourceRoot "src-tauri\src\lib.rs"
$windowFile = Join-Path $SourceRoot "src-tauri\src\app\window.rs"
$cargoToml = Join-Path $SourceRoot "src-tauri\Cargo.toml"
$cargoLock = Join-Path $SourceRoot "src-tauri\Cargo.lock"
$schemaFile = Join-Path $SourceRoot "node_modules\@tauri-apps\cli\config.schema.json"

$util = Get-Content -LiteralPath $utilFile -Raw
$lib = Get-Content -LiteralPath $libFile -Raw
$window = Get-Content -LiteralPath $windowFile -Raw
$cargo = Get-Content -LiteralPath $cargoToml -Raw
$lock = Get-Content -LiteralPath $cargoLock -Raw

foreach ($needle in @(
    "pub fn read_last_url",
    "pub fn write_last_url",
    "pub fn get_download_dir",
    "fn expand_download_dir"
)) {
    if ($util.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "util.rs was damaged by the portable patch: missing $needle"
    }
}

foreach ($needle in @(
    "PAKE_PORTABLE_WEBVIEW_V3",
    '.join("Data")',
    '.join("WebView")'
)) {
    if ($util.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable WebView patch is incomplete: missing $needle"
    }
}

foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_CONTEXT_V3",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    ".build(context)"
)) {
    if ($lib.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable Tauri override is incomplete: missing $needle"
    }
}

$windowCompact = [regex]::Replace($window,'\s+','')

if ($windowCompact.IndexOf("get_data_dir(",[StringComparison]::Ordinal) -lt 0) {
    throw "Pake no longer calls get_data_dir(...) for the WebView profile."
}
if ($windowCompact.IndexOf(".data_directory(_data_dir)",[StringComparison]::Ordinal) -lt 0) {
    throw "Pake no longer passes _data_dir to WebView data_directory(...)."
}

if ($cargo.IndexOf('webview2-com = "0.39.1"',[StringComparison]::Ordinal) -lt 0) {
    throw "webview2-com direct dependency is not aligned."
}
if ($cargo.IndexOf('windows-core = "0.62.2"',[StringComparison]::Ordinal) -lt 0) {
    throw "windows-core direct dependency is not aligned."
}

$m = [regex]::Match(
    $lock,
    '(?ms)\[\[package\]\]\s*name = "tauri-utils"\s*version = "([^"]+)"'
)
if (-not $m.Success -or [version]$m.Groups[1].Value -lt [version]"2.10.0") {
    throw "tauri-utils is too old for appDirectoriesOverride."
}

if (-not (Test-Path -LiteralPath $schemaFile -PathType Leaf)) {
    throw "Tauri CLI schema is missing."
}

$schema = Get-Content -LiteralPath $schemaFile -Raw
if ($schema.IndexOf('"appDirectoriesOverride"',[StringComparison]::Ordinal) -lt 0) {
    throw "Tauri CLI schema does not support appDirectoriesOverride."
}

Write-Host ""
Write-Host "Portable source verification PASS." -ForegroundColor Green
Write-Host "  Existing Pake helper functions preserved." -ForegroundColor Green
Write-Host "  WebView profile -> .\Data\WebView\<AppName>" -ForegroundColor Green
Write-Host "  Tauri/plugin data -> .\Data\App" -ForegroundColor Green
Write-Host "  Windows WebView2 dependency family aligned." -ForegroundColor Green
