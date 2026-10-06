param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Continue"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$revision = ""
try { $revision = (git -C $SourceRoot rev-parse HEAD).Trim() } catch {}

Set-Content -LiteralPath (Join-Path $OutputRoot "REVISION.txt") `
    -Encoding UTF8 `
    -Value $revision

try {
    git -C $SourceRoot diff -- `
        src-tauri/src/lib.rs `
        src-tauri/src/util.rs `
        src-tauri/Cargo.lock `
        package.json |
        Out-File -LiteralPath (Join-Path $OutputRoot "GIT-DIFF.txt") -Encoding UTF8
} catch {}

$copies = @(
    "src-tauri\src\lib.rs",
    "src-tauri\src\util.rs",
    "src-tauri\src\app\window.rs",
    "src-tauri\Cargo.toml",
    "src-tauri\Cargo.lock",
    "package.json",
    "pnpm-lock.yaml",
    "schema\pake.schema.json",
    ".pake-true-portable-patch.json",
    ".pake-portable-version-state.json",
    "src-tauri\.pake\tauri.conf.json",
    "src-tauri\.pake\pake.json"
)

foreach ($relative in $copies) {
    $src = Join-Path $SourceRoot $relative
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $safe = $relative -replace '[\\/:*?"<>|]','_'
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutputRoot $safe) -Force
    }
}

try {
    Push-Location (Join-Path $SourceRoot "src-tauri")
    cargo tree -i tauri 2>&1 |
        Out-File -LiteralPath (Join-Path $OutputRoot "CARGO-TAURI-TREE.txt") -Encoding UTF8
} catch {
} finally {
    Pop-Location
}

Write-Host "Failure diagnostics collected at $OutputRoot"


$runDir = Join-Path $SourceRoot ".pake-portable-run"

if (Test-Path -LiteralPath $runDir -PathType Container) {
    $runOut = Join-Path $OutputRoot "pake-portable-run"
    New-Item -ItemType Directory -Path $runOut -Force | Out-Null

    Get-ChildItem -LiteralPath $runDir -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $runOut $_.Name) -Force
        }
}
