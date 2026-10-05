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
$tauriRoot = Join-Path $SourceRoot "src-tauri"

if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
    throw "package.json was not found."
}

if (-not (Test-Path -LiteralPath $cargoLock -PathType Leaf)) {
    throw "src-tauri\Cargo.lock was not found."
}

Write-Host ""
Write-Host "Preparing temporary Pake checkout for Tauri portable-directory support." -ForegroundColor Yellow
Write-Host "This changes only GitHub's temporary checkout, not your clean Pake fork." -ForegroundColor Yellow

# Keep the JS-side Tauri CLI on the current 2.12 line so the config schema knows
# appDirectoriesOverride.
Run-Checked `
    -File "pnpm" `
    -Arguments @(
        "add",
        "@tauri-apps/cli@2.12.0",
        "--save-exact"
    ) `
    -WorkingDirectory $SourceRoot

# Upgrade the main Rust Tauri crate and LET CARGO RESOLVE its matching family.
#
# IMPORTANT:
# Do NOT force tauri-utils to exactly 2.10.0.
# With tauri 2.12.0, Cargo currently resolves tauri-macros/codegen 2.7.1,
# and those require tauri-utils ~2.10.1. The previous v1.2 script incorrectly
# forced 2.10.0 after Cargo had already selected the compatible 2.10.1.
Run-Checked `
    -File "cargo" `
    -Arguments @(
        "update",
        "-p","tauri",
        "--precise","2.12.0"
    ) `
    -WorkingDirectory $tauriRoot

# From this point forward, only VERIFY the resolved family. Do not downgrade
# tauri-build/tauri-utils independently from the compatible versions Cargo chose.
$lock = Get-Content -LiteralPath $cargoLock -Raw

function Get-Cargo-Version {
    param([string]$Name)

    $escaped = [regex]::Escape($Name)
    $m = [regex]::Match(
        $lock,
        "(?ms)\[\[package\]\]\s*name = `"$escaped`"\s*version = `"([^`"]+)`""
    )

    if (-not $m.Success) {
        return $null
    }

    try {
        return [version]$m.Groups[1].Value
    }
    catch {
        return $null
    }
}

$tauri = Get-Cargo-Version "tauri"
$utils = Get-Cargo-Version "tauri-utils"
$build = Get-Cargo-Version "tauri-build"
$macros = Get-Cargo-Version "tauri-macros"
$codegen = Get-Cargo-Version "tauri-codegen"

Write-Host ""
Write-Host "Cargo-resolved Tauri family:" -ForegroundColor Cyan
Write-Host "  tauri:         $tauri"
Write-Host "  tauri-utils:   $utils"
Write-Host "  tauri-build:   $build"
Write-Host "  tauri-macros:  $macros"
Write-Host "  tauri-codegen: $codegen"

if (-not $tauri -or $tauri -lt [version]"2.12.0") {
    throw "tauri was not upgraded to 2.12.0 or newer."
}

if (-not $utils -or $utils -lt [version]"2.10.0") {
    throw "tauri-utils is too old for appDirectoriesOverride."
}

if (-not $build -or $build -lt [version]"2.7.0") {
    throw "tauri-build is too old for the Tauri 2.12 portable config stack."
}

if (-not $macros -or $macros -lt [version]"2.7.0") {
    throw "tauri-macros is unexpectedly old."
}

if (-not $codegen -or $codegen -lt [version]"2.7.0") {
    throw "tauri-codegen is unexpectedly old."
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
Write-Host "Temporary Tauri checkout supports appDirectoriesOverride." -ForegroundColor Green
Write-Host "No Tauri family member was force-downgraded." -ForegroundColor Green
