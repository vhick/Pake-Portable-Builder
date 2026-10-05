param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$KitRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$Icon = "",
    [int]$Width = 1200,
    [int]$Height = 780,
    [bool]$ShowSystemTray = $true,
    [bool]$HideOnClose = $true,
    [bool]$StartToTray = $false,
    [bool]$Incognito = $false,
    [bool]$EnableFind = $true,
    [bool]$DarkMode = $false
)

$ErrorActionPreference = "Stop"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$KitRoot = [IO.Path]::GetFullPath($KitRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

if ([string]::IsNullOrWhiteSpace($Url)) { throw "URL is required." }
if ([string]::IsNullOrWhiteSpace($Name)) { throw "App name is required." }

if ($StartToTray -and -not $ShowSystemTray) {
    throw "StartToTray requires ShowSystemTray."
}

$args = @(
    "dist/cli.js",
    $Url,
    "--name", $Name,
    "--width", [string]$Width,
    "--height", [string]$Height,
    "--hide-on-close", $HideOnClose.ToString().ToLowerInvariant(),
    "--keep-binary"
)

if (-not [string]::IsNullOrWhiteSpace($Icon)) {
    $args += @("--icon",$Icon)
}
if ($ShowSystemTray) { $args += "--show-system-tray" }
if ($StartToTray) { $args += "--start-to-tray" }
if ($Incognito) { $args += "--incognito" }
if ($EnableFind) { $args += "--enable-find" }
if ($DarkMode) { $args += "--dark-mode" }

Write-Host ""
Write-Host "Building portable Pake app:" -ForegroundColor Cyan
Write-Host "  Name: $Name"
Write-Host "  URL:  $Url"
Write-Host ""
Write-Host ("node " + ($args -join " "))

Push-Location $SourceRoot
try {
    & node @args
    if ($LASTEXITCODE -ne 0) {
        throw "Pake CLI failed with exit code $LASTEXITCODE."
    }

    # Current Pake documentation says --keep-binary outputs AppName.exe on Windows.
    $builtExe = Join-Path $SourceRoot "$Name.exe"

    if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
        Write-Host "Expected root EXE was not found. Searching recent release EXEs..." -ForegroundColor Yellow

        $candidates = @(
            Get-ChildItem -LiteralPath (Join-Path $SourceRoot "src-tauri\target\release") `
                -Filter "*.exe" -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\deps\\' -and
                $_.Name -notmatch '(?i)build-script|installer|uninstall'
            } |
            Sort-Object LastWriteTime -Descending
        )

        if ($candidates.Count -eq 0) {
            throw "No Windows executable was found after Pake build."
        }

        $builtExe = $candidates[0].FullName
        Write-Host "Using fallback EXE: $builtExe"
    }

    & (Join-Path $KitRoot "scripts\Assemble-Pake-Portable.ps1") `
        -SourceRoot $SourceRoot `
        -KitRoot $KitRoot `
        -OutputRoot $OutputRoot `
        -BuiltExe $builtExe `
        -AppName $Name `
        -Url $Url

    # Pake's CLI may update Cargo.lock while preparing a generated app.
    # Restore it before another saved app is built.
    git checkout -- src-tauri/Cargo.lock 2>$null
}
finally {
    Pop-Location
}
