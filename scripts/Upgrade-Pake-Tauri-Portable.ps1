param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

function Run-Checked {
    param(
        [string]$File,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        Write-Host ""
        Write-Host ("> {0} {1}" -f $File,($Arguments -join " ")) -ForegroundColor Cyan
        & $File @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$File failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-Installed-Npm-Version {
    param(
        [string]$Root,
        [string]$PackageRelativePath
    )

    $pkg = Join-Path $Root ("node_modules\" + $PackageRelativePath + "\package.json")

    if (-not (Test-Path -LiteralPath $pkg -PathType Leaf)) {
        throw "Installed npm package metadata was not found: $pkg"
    }

    $json = Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
    return [version]([string]$json.version)
}

function Require-MajorMinor {
    param(
        [version]$Version,
        [int]$Major,
        [int]$Minor,
        [string]$Label
    )

    if ($Version.Major -ne $Major -or $Version.Minor -ne $Minor) {
        throw "$Label must be on $Major.$Minor.x but resolved to $Version"
    }
}

$packageJson = Join-Path $SourceRoot "package.json"
$cargoToml = Join-Path $SourceRoot "src-tauri\Cargo.toml"
$cargoLock = Join-Path $SourceRoot "src-tauri\Cargo.lock"
$tauriRoot = Join-Path $SourceRoot "src-tauri"

foreach ($file in @($packageJson,$cargoToml,$cargoLock)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required source file was not found: $file"
    }
}

Write-Host ""
Write-Host "Preparing ONLY GitHub's temporary Pake checkout." -ForegroundColor Yellow
Write-Host "Your clean Pake fork is not modified." -ForegroundColor Yellow

# -------------------------------------------------------------------
# JavaScript Tauri packages
#
# pnpm may preserve an existing manifest prefix (~ or ^) when an already
# declared dependency is updated. That is harmless. What matters to Tauri is
# the package version that is actually RESOLVED/INSTALLED.
# -------------------------------------------------------------------

Run-Checked `
    -File "pnpm" `
    -Arguments @(
        "add",
        "@tauri-apps/cli@2.12.1",
        "@tauri-apps/api@2.12.1"
    ) `
    -WorkingDirectory $SourceRoot

$installedCli = Get-Installed-Npm-Version `
    -Root $SourceRoot `
    -PackageRelativePath "@tauri-apps\cli"

$installedApi = Get-Installed-Npm-Version `
    -Root $SourceRoot `
    -PackageRelativePath "@tauri-apps\api"

Require-MajorMinor -Version $installedCli -Major 2 -Minor 12 -Label "@tauri-apps/cli"
Require-MajorMinor -Version $installedApi -Major 2 -Minor 12 -Label "@tauri-apps/api"

Write-Host ""
Write-Host "Installed JavaScript Tauri packages:" -ForegroundColor Cyan
Write-Host "  @tauri-apps/cli: $installedCli"
Write-Host "  @tauri-apps/api: $installedApi"

# -------------------------------------------------------------------
# Rust Tauri + Windows WebView2 direct dependencies
# -------------------------------------------------------------------

$cargo = Get-Content -LiteralPath $cargoToml -Raw

# Pin Tauri to the 2.12 line that contains appDirectoriesOverride.
$cargo = [regex]::Replace(
    $cargo,
    'tauri\s*=\s*\{\s*version\s*=\s*"(?:=?2\.[0-9.]+)"',
    'tauri = { version = "=2.12.1"',
    1
)

# Align Pake's direct COM interface dependencies with the WebView2 family
# used by Tauri 2.12/Wry on Windows.
$cargo = [regex]::Replace(
    $cargo,
    'webview2-com\s*=\s*"(?:=?0\.[0-9.]+)"',
    'webview2-com = "=0.39.1"',
    1
)

$cargo = [regex]::Replace(
    $cargo,
    'windows-core\s*=\s*"(?:=?0\.[0-9.]+)"',
    'windows-core = "=0.62.2"',
    1
)

Set-Content -LiteralPath $cargoToml -Value $cargo -Encoding UTF8

$cargoAfter = Get-Content -LiteralPath $cargoToml -Raw

foreach ($needle in @(
    'tauri = { version = "=2.12.1"',
    'webview2-com = "=0.39.1"',
    'windows-core = "=0.62.2"'
)) {
    if ($cargoAfter.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Cargo.toml alignment failed: missing $needle"
    }
}

Run-Checked `
    -File "cargo" `
    -Arguments @(
        "update",
        "-p","tauri",
        "--precise","2.12.1"
    ) `
    -WorkingDirectory $tauriRoot

# Resolve lockfile changes required by the direct dependency pins.
Run-Checked `
    -File "cargo" `
    -Arguments @(
        "metadata",
        "--format-version","1",
        "--no-deps"
    ) `
    -WorkingDirectory $tauriRoot

$lock = Get-Content -LiteralPath $cargoLock -Raw

function Get-Cargo-Versions {
    param([string]$Name)

    $escaped = [regex]::Escape($Name)

    return @(
        [regex]::Matches(
            $lock,
            "(?ms)\[\[package\]\]\s*name = `"$escaped`"\s*version = `"([^`"]+)`""
        ) |
        ForEach-Object { [version]$_.Groups[1].Value } |
        Sort-Object -Unique
    )
}

$tauriVersions = Get-Cargo-Versions "tauri"
$utilsVersions = Get-Cargo-Versions "tauri-utils"
$webviewVersions = Get-Cargo-Versions "webview2-com"
$windowsCoreVersions = Get-Cargo-Versions "windows-core"

Write-Host ""
Write-Host "Resolved Rust versions:" -ForegroundColor Cyan
Write-Host "  tauri:        $($tauriVersions -join ', ')"
Write-Host "  tauri-utils:  $($utilsVersions -join ', ')"
Write-Host "  webview2-com: $($webviewVersions -join ', ')"
Write-Host "  windows-core: $($windowsCoreVersions -join ', ')"

$rustTauri = @($tauriVersions | Where-Object {
    $_.Major -eq 2 -and $_.Minor -eq 12
})

if ($rustTauri.Count -eq 0) {
    throw "Rust tauri did not resolve to the 2.12.x line."
}

if (-not ($utilsVersions | Where-Object { $_ -ge [version]"2.10.0" })) {
    throw "tauri-utils is too old for appDirectoriesOverride."
}

# Confirm JS API and Rust Tauri share the same major/minor line.
Require-MajorMinor -Version $installedApi -Major 2 -Minor 12 -Label "@tauri-apps/api"

$schema = Join-Path $SourceRoot "node_modules\@tauri-apps\cli\config.schema.json"

if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw "Tauri CLI config schema was not found."
}

$schemaText = Get-Content -LiteralPath $schema -Raw

if ($schemaText.IndexOf('"appDirectoriesOverride"',[StringComparison]::Ordinal) -lt 0) {
    throw "Installed Tauri CLI schema does not contain appDirectoriesOverride."
}

# Store a tiny diagnostic marker for future failure artifacts.
[ordered]@{
    js_cli_installed = $installedCli.ToString()
    js_api_installed = $installedApi.ToString()
    rust_tauri = @($tauriVersions | ForEach-Object { $_.ToString() })
    tauri_utils = @($utilsVersions | ForEach-Object { $_.ToString() })
    webview2_com = @($webviewVersions | ForEach-Object { $_.ToString() })
    windows_core = @($windowsCoreVersions | ForEach-Object { $_.ToString() })
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-portable-version-state.json") -Encoding UTF8

Write-Host ""
Write-Host "Tauri resolved-version alignment PASS." -ForegroundColor Green
Write-Host "  JS API/CLI: installed 2.12.x" -ForegroundColor Green
Write-Host "  Rust tauri: resolved 2.12.x" -ForegroundColor Green
Write-Host "  Manifest prefixes (~ or ^) are intentionally not treated as errors." -ForegroundColor Green
