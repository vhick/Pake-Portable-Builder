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

Run-Checked `
    -File "pnpm" `
    -Arguments @(
        "add",
        "@tauri-apps/cli@2.12.0",
        "--save-exact"
    ) `
    -WorkingDirectory $SourceRoot

Run-Checked `
    -File "cargo" `
    -Arguments @(
        "update",
        "-p","tauri",
        "--precise","2.12.0"
    ) `
    -WorkingDirectory $tauriRoot

$cargo = Get-Content -LiteralPath $cargoToml -Raw

if ($cargo -notmatch 'webview2-com\s*=\s*"0\.38"') {
    throw "Expected Pake direct webview2-com 0.38 dependency was not found. Re-inspect before changing versions."
}

if ($cargo -notmatch 'windows-core\s*=\s*"0\.61\.2"') {
    throw "Expected Pake direct windows-core 0.61.2 dependency was not found. Re-inspect before changing versions."
}

$cargo = $cargo -replace 'webview2-com\s*=\s*"0\.38"','webview2-com = "0.39.1"'
$cargo = $cargo -replace 'windows-core\s*=\s*"0\.61\.2"','windows-core = "0.62.2"'

Set-Content -LiteralPath $cargoToml -Value $cargo -Encoding UTF8

Run-Checked `
    -File "cargo" `
    -Arguments @("update") `
    -WorkingDirectory $tauriRoot

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
Write-Host "Resolved versions:" -ForegroundColor Cyan
Write-Host "  tauri:        $($tauriVersions -join ', ')"
Write-Host "  tauri-utils:  $($utilsVersions -join ', ')"
Write-Host "  webview2-com: $($webviewVersions -join ', ')"
Write-Host "  windows-core: $($windowsCoreVersions -join ', ')"

if (-not ($tauriVersions | Where-Object { [version]$_ -ge [version]"2.12.0" })) {
    throw "Tauri 2.12+ was not resolved."
}

if (-not ($utilsVersions | Where-Object { [version]$_ -ge [version]"2.10.0" })) {
    throw "tauri-utils 2.10+ was not resolved."
}

$cargoAfter = Get-Content -LiteralPath $cargoToml -Raw

if ($cargoAfter.IndexOf('webview2-com = "0.39.1"',[StringComparison]::Ordinal) -lt 0) {
    throw "Pake direct webview2-com dependency was not aligned to 0.39.1."
}
if ($cargoAfter.IndexOf('windows-core = "0.62.2"',[StringComparison]::Ordinal) -lt 0) {
    throw "Pake direct windows-core dependency was not aligned to 0.62.2."
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
Write-Host "Temporary dependency alignment PASS." -ForegroundColor Green
