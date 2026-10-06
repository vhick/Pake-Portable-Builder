param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()
$report = Join-Path $OutputRoot "PAKE-STORAGE-PATH-INVENTORY.txt"
$sourceOut = Join-Path $OutputRoot "RelevantSource"
New-Item -ItemType Directory -Path $sourceOut -Force | Out-Null

$terms = @(
    "get_data_dir",
    "data_directory",
    "app_data_dir",
    "app_config_dir",
    "app_local_data_dir",
    "app_cache_dir",
    "app_log_dir",
    "config_dir",
    "data_dir",
    "local_data_dir",
    "cache_dir",
    "download_dir",
    "home_dir",
    "last-url",
    "window-state",
    "WindowStatePlugin",
    "current_exe",
    "AppDirectoriesOverride",
    "SetCurrentProcessExplicitAppUserModelID",
    "registry",
    "winreg",
    "HKCU"
)

Set-Content -LiteralPath $report -Encoding UTF8 -Value @(
    "PAKE STORAGE-PATH INVENTORY",
    "Revision: $revision",
    "Generated: $(Get-Date)",
    "",
    "SOURCE ONLY. This does not read your PC's AppData, registry, cookies, website logins or local Pake apps.",
    ""
)

$root = Join-Path $SourceRoot "src-tauri\src"
$candidates = @{}

Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.rs" |
    ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) { return }

        foreach ($term in $terms) {
            if ($content.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $candidates[$_.FullName] = $true
                break
            }
        }
    }

foreach ($filePath in ($candidates.Keys | Sort-Object)) {
    $rel = $filePath.Substring($SourceRoot.Length).TrimStart('\')
    $dest = Join-Path $sourceOut $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $filePath -Destination $dest -Force

    Add-Content -LiteralPath $report -Encoding UTF8 -Value @(
        ("=" * 78),
        "FILE: $rel",
        ("=" * 78)
    )

    $lines = Get-Content -LiteralPath $filePath
    for ($i=0; $i -lt $lines.Count; $i++) {
        $match = $false
        foreach ($term in $terms) {
            if ([string]$lines[$i] -match [regex]::Escape($term)) {
                $match = $true
                break
            }
        }

        if (-not $match) { continue }

        $from = [Math]::Max(0,$i-5)
        $to = [Math]::Min($lines.Count-1,$i+10)

        for ($j=$from; $j -le $to; $j++) {
            Add-Content -LiteralPath $report -Encoding UTF8 `
                -Value ("{0,5}: {1}" -f ($j+1),$lines[$j])
        }
        Add-Content -LiteralPath $report -Encoding UTF8 -Value ""
    }
}

foreach ($relative in @(
    "src-tauri\Cargo.toml",
    "src-tauri\Cargo.lock",
    "package.json",
    "pnpm-lock.yaml"
)) {
    $src = Join-Path $SourceRoot $relative
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $name = $relative -replace '[\\/:*?"<>|]','_'
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutputRoot $name) -Force
    }
}

Set-Content -LiteralPath (Join-Path $OutputRoot "UPSTREAM-REVISION.txt") `
    -Encoding UTF8 `
    -Value $revision

Write-Host "Pake storage-path inspection prepared at $OutputRoot" -ForegroundColor Green
