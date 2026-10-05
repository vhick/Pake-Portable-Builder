param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)

$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

$files = @(
    "src-tauri\src\util.rs",
    "src-tauri\src\lib.rs",
    "src-tauri\src\app\window.rs",
    "src-tauri\src\app\invoke.rs",
    "src-tauri\Cargo.toml",
    "src-tauri\tauri.conf.json",
    "src-tauri\pake.json",
    "package.json",
    "pnpm-lock.yaml",
    "docs\cli-usage.md"
)

foreach ($relative in $files) {
    $source = Join-Path $SourceRoot $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $dest = Join-Path $OutputRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}

Set-Content -LiteralPath (Join-Path $OutputRoot "UPSTREAM-REVISION.txt") `
    -Encoding UTF8 `
    -Value $revision

Write-Host "Pake source inspection prepared at $OutputRoot" -ForegroundColor Green
