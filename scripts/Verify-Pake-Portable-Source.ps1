param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"

$utilFile = Join-Path $SourceRoot "src-tauri\src\util.rs"
$libFile = Join-Path $SourceRoot "src-tauri\src\lib.rs"
$windowFile = Join-Path $SourceRoot "src-tauri\src\app\window.rs"
$packageFile = Join-Path $SourceRoot "package.json"

$util = Get-Content -LiteralPath $utilFile -Raw
$lib = Get-Content -LiteralPath $libFile -Raw
$window = Get-Content -LiteralPath $windowFile -Raw
$package = Get-Content -LiteralPath $packageFile -Raw | ConvertFrom-Json

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
    "PAKE_TRUE_PORTABLE_V1",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    ".build(portable_context)"
)) {
    if ($lib.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Portable Tauri path verification failed: missing $needle"
    }
}

# This is the upstream behavior that makes the separate WebView path patch necessary.
foreach ($needle in @(
    "get_data_dir(app, package_name)",
    ".data_directory(_data_dir)"
)) {
    if ($window.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Pake WebView path implementation changed upstream: missing $needle"
    }
}

$tauriCli = [string]$package.dependencies.'@tauri-apps/cli'
Write-Host "Pake @tauri-apps/cli dependency: $tauriCli"

Write-Host ""
Write-Host "Portable source verification PASS." -ForegroundColor Green
