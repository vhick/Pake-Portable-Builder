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

foreach ($needle in @(
    '.join("Data")',
    '.join("WebView")',
    'current_exe()'
)) {
    if ($util.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable WebView path verification failed: missing $needle"
    }
}

foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_V2",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    ".build(portable_context)"
)) {
    if ($lib.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable Tauri path verification failed: missing $needle"
    }
}

foreach ($needle in @(
    "get_data_dir(app, package_name)",
    ".data_directory(_data_dir)"
)) {
    if ($window.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Pake WebView implementation changed upstream: missing $needle"
    }
}

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
