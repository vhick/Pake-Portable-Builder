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
$cargoLock = Join-Path $SourceRoot "src-tauri\Cargo.lock"

if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
    throw "package.json was not found."
}
if (-not (Test-Path -LiteralPath $cargoLock -PathType Leaf)) {
    throw "src-tauri\Cargo.lock was not found."
}

Write-Host ""
Write-Host "Preparing temporary Pake checkout for Tauri portable-directory support." -ForegroundColor Yellow
Write-Host "This changes only the GitHub Actions checkout, not your clean Pake fork." -ForegroundColor Yellow

# Pake's current JS CLI may be older than the config schema that knows
# appDirectoriesOverride. Upgrade only the temporary checkout.
Run-Checked `
    -File "pnpm" `
    -Arguments @("add","@tauri-apps/cli@2.12.0","--save-exact") `
    -WorkingDirectory $SourceRoot

# Move the Rust stack to the first stable line we already use for true-portable
# Tauri builds. Cargo resolves the matching runtime/codegen dependencies.
$tauriRoot = Join-Path $SourceRoot "src-tauri"

Run-Checked `
    -File "cargo" `
    -Arguments @("update","-p","tauri","--precise","2.12.0") `
    -WorkingDirectory $tauriRoot

Run-Checked `
    -File "cargo" `
    -Arguments @("update","-p","tauri-build","--precise","2.7.0") `
    -WorkingDirectory $tauriRoot

# The portable-directory config itself was introduced in tauri-utils 2.10.0.
Run-Checked `
    -File "cargo" `
    -Arguments @("update","-p","tauri-utils","--precise","2.10.0") `
    -WorkingDirectory $tauriRoot

$lock = Get-Content -LiteralPath $cargoLock -Raw

function Get-Cargo-Version {
    param([string]$Name)

    $escaped = [regex]::Escape($Name)
    $m = [regex]::Match(
        $lock,
        "(?ms)\[\[package\]\]\s*name = `"$escaped`"\s*version = `"([^`"]+)`""
    )

    if (-not $m.Success) { return $null }

    try { return [version]$m.Groups[1].Value }
    catch { return $null }
}

$tauri = Get-Cargo-Version "tauri"
$utils = Get-Cargo-Version "tauri-utils"
$build = Get-Cargo-Version "tauri-build"

Write-Host ""
Write-Host "Temporary Tauri versions:" -ForegroundColor Cyan
Write-Host "  tauri:       $tauri"
Write-Host "  tauri-utils: $utils"
Write-Host "  tauri-build: $build"

if (-not $tauri -or $tauri -lt [version]"2.12.0") {
    throw "tauri was not upgraded to 2.12.0 or newer."
}
if (-not $utils -or $utils -lt [version]"2.10.0") {
    throw "tauri-utils is too old for appDirectoriesOverride."
}
if (-not $build -or $build -lt [version]"2.7.0") {
    throw "tauri-build is too old for the updated portable config stack."
}

$schema = Join-Path $SourceRoot "node_modules\@tauri-apps\cli\config.schema.json"
if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw "Tauri CLI config schema was not found."
}

$schemaText = Get-Content -LiteralPath $schema -Raw
if ($schemaText.IndexOf('"appDirectoriesOverride"',[StringComparison]::Ordinal) -lt 0) {
    throw "Installed Tauri CLI schema still does not contain appDirectoriesOverride."
}

Write-Host ""
Write-Host "Temporary Tauri checkout supports appDirectoriesOverride." -ForegroundColor Green
