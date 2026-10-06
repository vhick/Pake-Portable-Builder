param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"

$utilFile = Join-Path $SourceRoot "src-tauri\src\util.rs"
$libFile = Join-Path $SourceRoot "src-tauri\src\lib.rs"
$windowFile = Join-Path $SourceRoot "src-tauri\src\app\window.rs"
$cargoLockFile = Join-Path $SourceRoot "src-tauri\Cargo.lock"
$schemaFile = Join-Path $SourceRoot "node_modules\@tauri-apps\cli\config.schema.json"

$util = Get-Content -LiteralPath $utilFile -Raw
$lib = Get-Content -LiteralPath $libFile -Raw
$window = Get-Content -LiteralPath $windowFile -Raw
$lock = Get-Content -LiteralPath $cargoLockFile -Raw

# 1. Verify the patched WebView path function.
foreach ($needle in @(
    "PAKE_PORTABLE_WEBVIEW_V2",
    '.join("Data")',
    '.join("WebView")',
    'current_exe()'
)) {
    if ($util.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable WebView verification failed in util.rs: missing $needle"
    }
}

# 2. Verify the Tauri/plugin portable override.
foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_CONTEXT_V2",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    "context.config_mut().app.app_directories_override"
)) {
    if ($lib.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable Tauri verification failed in lib.rs: missing $needle"
    }
}

# Prove Pake still creates/uses a mutable Tauri context.
$libCompact = [regex]::Replace($lib,'\s+','')

if ($libCompact.IndexOf("generate_context!()",[StringComparison]::Ordinal) -lt 0) {
    throw "Could not prove that Pake still creates a Tauri context."
}

# 3. Verify behavior, not one exact argument spelling.
#
# We only need to prove:
#   a) window.rs still calls get_data_dir(...)
#   b) that _data_dir is still passed to WebView data_directory(...)
#
# This intentionally permits harmless upstream changes such as
# package_name.clone() or spacing/formatting differences.

$windowCompact = [regex]::Replace($window,'\s+','')

if ($windowCompact.IndexOf("get_data_dir(",[StringComparison]::Ordinal) -lt 0) {
    throw "Pake WebView implementation changed upstream: no get_data_dir(...) call was found."
}

if ($windowCompact.IndexOf(".data_directory(_data_dir)",[StringComparison]::Ordinal) -lt 0) {
    throw "Pake WebView implementation changed upstream: the WebView no longer uses _data_dir as data_directory."
}

# 4. Verify the upgraded Tauri stack supports appDirectoriesOverride.
$m = [regex]::Match(
    $lock,
    '(?ms)\[\[package\]\]\s*name = "tauri-utils"\s*version = "([^"]+)"'
)

if (-not $m.Success) {
    throw "Could not determine tauri-utils version."
}

$utilsVersion = [version]$m.Groups[1].Value
Write-Host "tauri-utils: $utilsVersion"

if ($utilsVersion -lt [version]"2.10.0") {
    throw "tauri-utils is too old for appDirectoriesOverride."
}

if (-not (Test-Path -LiteralPath $schemaFile -PathType Leaf)) {
    throw "Tauri CLI schema is missing."
}

$schema = Get-Content -LiteralPath $schemaFile -Raw

if ($schema.IndexOf('"appDirectoriesOverride"',[StringComparison]::Ordinal) -lt 0) {
    throw "Tauri CLI schema does not know appDirectoriesOverride."
}

Write-Host ""
Write-Host "Portable source verification PASS." -ForegroundColor Green
Write-Host "  Tauri/plugin data -> .\Data\App" -ForegroundColor Green
Write-Host "  WebView data      -> .\Data\WebView\<AppName>" -ForegroundColor Green
