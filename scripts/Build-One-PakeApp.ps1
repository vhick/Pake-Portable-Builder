param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$KitRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$Name,

    # Basic / existing options
    [string]$Icon = "",
    [int]$Width = 1200,
    [int]$Height = 780,
    [bool]$ShowSystemTray = $true,
    [bool]$HideOnClose = $true,
    [bool]$StartToTray = $false,
    [bool]$Incognito = $false,
    [bool]$EnableFind = $true,
    [bool]$DarkMode = $false,

    # Windows-focused interactive options
    [int]$MinWidth = 0,
    [int]$MinHeight = 0,
    [int]$Zoom = 100,
    [bool]$HideWindowDecorations = $false,
    [bool]$Fullscreen = $false,
    [bool]$Maximize = $false,
    [string]$ActivationShortcut = "",
    [bool]$AlwaysOnTop = $false,
    [bool]$ForceInternalNavigation = $false,
    [bool]$MultiWindow = $false,
    [bool]$NewWindow = $false,

    # Additional Windows-capable Pake options.
    # These are supported by saved apps/*.json even though GitHub's manual
    # workflow form cannot expose every option because workflow_dispatch is
    # limited to 25 top-level inputs.
    [string]$Title = "",
    [bool]$DisabledWebShortcuts = $false,
    [string]$InternalUrlRegex = "",
    [string]$SafeDomain = "",
    [string]$UserAgent = "",
    [string]$SystemTrayIcon = "",
    [bool]$Wasm = $false,
    [bool]$EnableDragDrop = $false,
    [bool]$MultiInstance = $false,
    [string]$ProxyUrl = "",
    [bool]$Debug = $false,
    [bool]$IgnoreCertificateErrors = $false,
    [string]$Targets = "x64",
    [string]$AppVersion = ""
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

if ($Zoom -lt 50 -or $Zoom -gt 200) {
    throw "Zoom must be between 50 and 200."
}

if ($MinWidth -lt 0 -or $MinHeight -lt 0) {
    throw "MinWidth and MinHeight cannot be negative."
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

# Basic values
if (-not [string]::IsNullOrWhiteSpace($Icon)) {
    $args += @("--icon",$Icon)
}
if ($ShowSystemTray) { $args += "--show-system-tray" }
if ($StartToTray) { $args += "--start-to-tray" }
if ($Incognito) { $args += "--incognito" }
if ($EnableFind) { $args += "--enable-find" }
if ($DarkMode) { $args += "--dark-mode" }

# Window sizing / zoom
if ($MinWidth -gt 0) { $args += @("--min-width",[string]$MinWidth) }
if ($MinHeight -gt 0) { $args += @("--min-height",[string]$MinHeight) }
if ($Zoom -ne 100) { $args += @("--zoom",[string]$Zoom) }

# Windows window behavior
if ($HideWindowDecorations) { $args += "--hide-window-decorations" }
if ($Fullscreen) { $args += "--fullscreen" }
if ($Maximize) { $args += "--maximize" }
if ($AlwaysOnTop) { $args += "--always-on-top" }

if (-not [string]::IsNullOrWhiteSpace($ActivationShortcut)) {
    $args += @("--activation-shortcut",$ActivationShortcut)
}

if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $args += @("--title",$Title)
}

# Keep Pake's built-in Windows web shortcuts ENABLED by default.
# Only pass this flag when the saved app explicitly asks to disable them.
if ($DisabledWebShortcuts) { $args += "--disabled-web-shortcuts" }

# Navigation and popup behavior
if ($ForceInternalNavigation) { $args += "--force-internal-navigation" }

if (-not [string]::IsNullOrWhiteSpace($InternalUrlRegex)) {
    $args += @("--internal-url-regex",$InternalUrlRegex)
}

if (-not [string]::IsNullOrWhiteSpace($SafeDomain)) {
    $args += @("--safe-domain",$SafeDomain)
}

if ($NewWindow) { $args += "--new-window" }
if ($MultiWindow) { $args += "--multi-window" }
if ($MultiInstance) { $args += "--multi-instance" }

# Browser / WebView behavior
if (-not [string]::IsNullOrWhiteSpace($UserAgent)) {
    $args += @("--user-agent",$UserAgent)
}

if ($Wasm) { $args += "--wasm" }
if ($EnableDragDrop) { $args += "--enable-drag-drop" }
if ($Debug) { $args += "--debug" }
if ($IgnoreCertificateErrors) { $args += "--ignore-certificate-errors" }

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $args += @("--proxy-url",$ProxyUrl)
}

# Tray customization
if (-not [string]::IsNullOrWhiteSpace($SystemTrayIcon)) {
    if (-not $ShowSystemTray) {
        throw "SystemTrayIcon requires ShowSystemTray."
    }
    $args += @("--system-tray-icon",$SystemTrayIcon)
}

# Windows build architecture.
if (-not [string]::IsNullOrWhiteSpace($Targets)) {
    if ($Targets -notin @("x64","arm64")) {
        throw "For this Windows builder, Targets must be x64 or arm64."
    }
    $args += @("--targets",$Targets)
}

if (-not [string]::IsNullOrWhiteSpace($AppVersion)) {
    $args += @("--app-version",$AppVersion)
}

Write-Host ""
Write-Host "Building portable Pake app:" -ForegroundColor Cyan
Write-Host "  Name: $Name"
Write-Host "  URL:  $Url"
Write-Host "  Zoom: $Zoom%"
Write-Host "  Built-in web shortcuts disabled: $DisabledWebShortcuts"
Write-Host "  Multi-window: $MultiWindow"
Write-Host "  New-window/popups: $NewWindow"
Write-Host ""
Write-Host ("node " + ($args -join " "))

Push-Location $SourceRoot
try {
    & node @args
    if ($LASTEXITCODE -ne 0) {
        throw "Pake CLI failed with exit code $LASTEXITCODE."
    }

    # Pake --keep-binary outputs AppName.exe on Windows.
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
