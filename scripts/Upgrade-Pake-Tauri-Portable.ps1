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
# Keep the JavaScript Tauri packages on the SAME major/minor as the
# Rust Tauri crate.
#
# Tauri CLI rejects builds when @tauri-apps/api and Rust tauri are on
# different major/minor lines. The previous builder upgraded the CLI but
# left @tauri-apps/api at 2.10.x, while Rust tauri resolved to 2.12.x.
# -------------------------------------------------------------------

Run-Checked `
    -File "pnpm" `
    -Arguments @(
        "add",
        "@tauri-apps/cli@2.12.1",
        "@tauri-apps/api@2.12.1",
        "--save-exact"
    ) `
    -WorkingDirectory $SourceRoot

# -------------------------------------------------------------------
# Pin only the direct Rust dependencies we intentionally need to move.
# Do NOT run a blanket `cargo update`: the previous v3.0 script updated
# unrelated plugins and dozens of unrelated crates.
# -------------------------------------------------------------------

$cargo = Get-Content -LiteralPath $cargoToml -Raw

# Pin Tauri to the 2.12 line that contains appDirectoriesOverride.
$cargo = [regex]::Replace(
    $cargo,
    'tauri\s*=\s*\{\s*version\s*=\s*"2\.10\.2"',
    'tauri = { version = "=2.12.1"',
    1
)

# Keep Pake's direct WebView2 COM interfaces on the same family used by
# Tauri 2.12 / Wry on Windows.
$cargo = [regex]::Replace(
    $cargo,
    'webview2-com\s*=\s*"0\.38"',
    'webview2-com = "=0.39.1"',
    1
)

$cargo = [regex]::Replace(
    $cargo,
    'windows-core\s*=\s*"0\.61\.2"',
    'windows-core = "=0.62.2"',
    1
)

Set-Content -LiteralPath $cargoToml -Value $cargo -Encoding UTF8

# Validate that all three intended direct pins are present.
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

# Update ONLY the Tauri package selection. Cargo keeps unrelated plugin
# versions from the existing lockfile unless the new Tauri graph requires
# a transitive change.
Run-Checked `
    -File "cargo" `
    -Arguments @(
        "update",
        "-p","tauri",
        "--precise","2.12.1"
    ) `
    -WorkingDirectory $tauriRoot

# A normal metadata resolution updates lock entries required by the changed
# direct WebView2 dependencies without compiling the application.
Run-Checked `
    -File "cargo" `
    -Arguments @(
        "metadata",
        "--format-version","1",
        "--no-deps"
    ) `
    -WorkingDirectory $tauriRoot

# -------------------------------------------------------------------
# Verify JavaScript package alignment.
# -------------------------------------------------------------------

$pkg = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
$jsCli = [string]$pkg.dependencies.'@tauri-apps/cli'
$jsApi = [string]$pkg.dependencies.'@tauri-apps/api'

Write-Host ""
Write-Host "JavaScript Tauri packages:" -ForegroundColor Cyan
Write-Host "  @tauri-apps/cli: $jsCli"
Write-Host "  @tauri-apps/api: $jsApi"

if ($jsCli -ne "2.12.1") {
    throw "@tauri-apps/cli is not exactly 2.12.1."
}
if ($jsApi -ne "2.12.1") {
    throw "@tauri-apps/api is not exactly 2.12.1."
}

# -------------------------------------------------------------------
# Verify the Rust lockfile now has the portable-directory-capable stack.
# -------------------------------------------------------------------

$lock = Get-Content -LiteralPath $cargoLock -Raw

function Get-Versions {
    param([string]$Name)

    $escaped = [regex]::Escape($Name)
    return @(
        [regex]::Matches(
            $lock,
            "(?ms)\[\[package\]\]\s*name = `"$escaped`"\s*version = `"([^`"]+)`""
        ) |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
    )
}

$tauriVersions = Get-Versions "tauri"
$utilsVersions = Get-Versions "tauri-utils"
$webviewVersions = Get-Versions "webview2-com"
$windowsCoreVersions = Get-Versions "windows-core"

Write-Host ""
Write-Host "Resolved Rust versions:" -ForegroundColor Cyan
Write-Host "  tauri:        $($tauriVersions -join ', ')"
Write-Host "  tauri-utils:  $($utilsVersions -join ', ')"
Write-Host "  webview2-com: $($webviewVersions -join ', ')"
Write-Host "  windows-core: $($windowsCoreVersions -join ', ')"

if (-not ($tauriVersions | Where-Object { [version]$_ -eq [version]"2.12.1" })) {
    throw "Rust tauri 2.12.1 was not resolved."
}

if (-not ($utilsVersions | Where-Object { [version]$_ -ge [version]"2.10.0" })) {
    throw "tauri-utils is too old for appDirectoriesOverride."
}

$schema = Join-Path $SourceRoot "node_modules\@tauri-apps\cli\config.schema.json"

if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw "Tauri CLI config schema was not found."
}

$schemaText = Get-Content -LiteralPath $schema -Raw

if ($schemaText.IndexOf('"appDirectoriesOverride"',[StringComparison]::Ordinal) -lt 0) {
    throw "Installed Tauri CLI schema does not contain appDirectoriesOverride."
}

Write-Host ""
Write-Host "Tauri version alignment PASS." -ForegroundColor Green
Write-Host "  JS API/CLI: 2.12.1" -ForegroundColor Green
Write-Host "  Rust tauri: 2.12.1" -ForegroundColor Green
Write-Host "  No blanket cargo update was used." -ForegroundColor Green
