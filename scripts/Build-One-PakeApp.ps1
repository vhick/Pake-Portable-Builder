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
    [bool]$DarkMode = $false,

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

    # Empty = let Pake auto-detect the native Windows architecture.
    [string]$Targets = "",

    [string]$AppVersion = ""
)

$ErrorActionPreference = "Stop"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$KitRoot = [IO.Path]::GetFullPath($KitRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "URL is required."
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    throw "App name is required."
}

if ($StartToTray -and -not $ShowSystemTray) {
    throw "StartToTray requires ShowSystemTray."
}

if (-not [string]::IsNullOrWhiteSpace($SystemTrayIcon) -and -not $ShowSystemTray) {
    throw "SystemTrayIcon requires ShowSystemTray."
}

if ($Zoom -lt 50 -or $Zoom -gt 200) {
    throw "Zoom must be between 50 and 200."
}

if ($MinWidth -lt 0 -or $MinHeight -lt 0) {
    throw "MinWidth and MinHeight cannot be negative."
}

if (
    -not [string]::IsNullOrWhiteSpace($Targets) -and
    $Targets -notin @("x64","arm64")
) {
    throw "For this Windows builder, Targets must be blank, x64, or arm64."
}

# -------------------------------------------------------------------
# Build through Pake's DECLARATIVE JSON config interface.
#
# This is more robust than assembling a long command line. Pake publishes a
# schema for the config file and validates unknown fields/types/ranges itself.
# -------------------------------------------------------------------

$config = [ordered]@{
    url = $Url
    name = $Name
    width = $Width
    height = $Height
    minWidth = $MinWidth
    minHeight = $MinHeight
    zoom = $Zoom

    showSystemTray = $ShowSystemTray
    hideOnClose = $HideOnClose
    startToTray = $StartToTray

    incognito = $Incognito
    enableFind = $EnableFind
    darkMode = $DarkMode
    disabledWebShortcuts = $DisabledWebShortcuts

    hideWindowDecorations = $HideWindowDecorations
    fullscreen = $Fullscreen
    maximize = $Maximize
    alwaysOnTop = $AlwaysOnTop

    forceInternalNavigation = $ForceInternalNavigation
    newWindow = $NewWindow
    multiWindow = $MultiWindow
    multiInstance = $MultiInstance

    wasm = $Wasm
    enableDragDrop = $EnableDragDrop
    debug = $Debug
    ignoreCertificateErrors = $IgnoreCertificateErrors

    # We need the standalone EXE for the portable package.
    keepBinary = $true
}

# Only include optional strings when the user supplied a value.
$optionalStrings = [ordered]@{
    icon = $Icon
    title = $Title
    activationShortcut = $ActivationShortcut
    internalUrlRegex = $InternalUrlRegex
    safeDomain = $SafeDomain
    userAgent = $UserAgent
    systemTrayIcon = $SystemTrayIcon
    proxyUrl = $ProxyUrl
    targets = $Targets
    appVersion = $AppVersion
}

foreach ($item in $optionalStrings.GetEnumerator()) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item.Value)) {
        $config[$item.Key] = [string]$item.Value
    }
}

# -------------------------------------------------------------------
# Validate our generated field names against the exact Pake checkout.
# If Pake removes or renames a config field in the future, fail here with a
# clean message instead of reaching a cryptic build error.
# -------------------------------------------------------------------

$schemaFile = Join-Path $SourceRoot "schema\pake.schema.json"

if (Test-Path -LiteralPath $schemaFile -PathType Leaf) {
    $schema = Get-Content -LiteralPath $schemaFile -Raw | ConvertFrom-Json
    $allowed = @($schema.properties.PSObject.Properties.Name)

    foreach ($key in $config.Keys) {
        if ($key -notin $allowed) {
            throw "Current Pake schema does not support config field '$key'. Run inspect-storage / inspect upstream before rebuilding."
        }
    }
}
else {
    Write-Host "Pake schema file was not found; continuing with CLI validation." -ForegroundColor Yellow
}

# Keep all run-time troubleshooting material in one known directory.
$runDir = Join-Path $SourceRoot ".pake-portable-run"

if (Test-Path -LiteralPath $runDir) {
    Remove-Item -LiteralPath $runDir -Recurse -Force
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$configPath = Join-Path $runDir "pake-build-config.json"
$stdoutPath = Join-Path $runDir "pake-stdout.json"
$stderrPath = Join-Path $runDir "pake-stderr.log"
$helpPath = Join-Path $runDir "pake-help.txt"

$config |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $configPath -Encoding UTF8

Write-Host ""
Write-Host "Generated Pake build config:" -ForegroundColor Cyan
Write-Host "  $configPath"
Write-Host ""
Get-Content -LiteralPath $configPath | ForEach-Object { Write-Host $_ }

# Capture the exact CLI help from the checked-out revision for diagnostics.
Push-Location $SourceRoot
try {
    & node "dist/cli.js" --help 2>&1 |
        Out-File -LiteralPath $helpPath -Encoding UTF8
}
finally {
    Pop-Location
}

# -------------------------------------------------------------------
# Run Pake in machine-readable JSON mode.
#
# Pake documents that --json keeps stdout as one JSON object and sends logs
# to stderr. Capturing the two streams separately makes future failures much
# easier to diagnose.
# -------------------------------------------------------------------

$argumentList = @(
    "dist/cli.js",
    "--config", $configPath,
    "--json"
)

Write-Host ""
Write-Host "Running Pake via JSON config..." -ForegroundColor Cyan
Write-Host "  node dist/cli.js --config <generated-config> --json"
Write-Host ""

$process = Start-Process `
    -FilePath "node" `
    -ArgumentList $argumentList `
    -WorkingDirectory $SourceRoot `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $stderrText = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Write-Host "Pake build log:" -ForegroundColor DarkGray
        Write-Host $stderrText
    }
}

$stdoutText = ""
if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $stdoutText = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
}

$result = $null
if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
    try {
        $result = $stdoutText | ConvertFrom-Json
    }
    catch {
        Write-Host "Pake stdout was not valid JSON:" -ForegroundColor Yellow
        Write-Host $stdoutText
    }
}

if ($process.ExitCode -ne 0) {
    $details = "Pake CLI failed with exit code $($process.ExitCode)."

    if ($null -ne $result -and $null -ne $result.error) {
        $code = [string]$result.error.code
        $message = [string]$result.error.message
        $hint = [string]$result.error.hint

        if ($code) { $details += " Code: $code." }
        if ($message) { $details += " Message: $message" }
        if ($hint) { $details += " Hint: $hint" }
    }

    throw $details
}

if ($null -ne $result -and $result.PSObject.Properties.Name -contains "ok") {
    if (-not [bool]$result.ok) {
        throw "Pake returned ok=false even though the process exit code was zero."
    }
}

# -------------------------------------------------------------------
# Locate the standalone EXE.
# Current Pake documents AppName.exe on Windows when keepBinary=true.
# -------------------------------------------------------------------

$builtExe = Join-Path $SourceRoot "$Name.exe"

if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
    # Prefer any JSON-reported .exe output that actually exists.
    if ($null -ne $result -and $null -ne $result.outputs) {
        foreach ($output in @($result.outputs)) {
            $candidate = [string]$output.path

            if (
                -not [string]::IsNullOrWhiteSpace($candidate) -and
                $candidate.EndsWith(".exe",[StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $candidate -PathType Leaf)
            ) {
                $builtExe = $candidate
                break
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
    Write-Host "Expected root EXE was not found. Searching recent Windows EXEs..." -ForegroundColor Yellow

    $searchRoots = @(
        $SourceRoot,
        (Join-Path $SourceRoot "src-tauri\target\release")
    )

    $candidates = @()

    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            continue
        }

        $candidates += @(
            Get-ChildItem -LiteralPath $searchRoot -Filter "*.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\deps\\' -and
                $_.Name -notmatch '(?i)uninstall|setup|installer|build-script'
            }
        )
    }

    $builtExe = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

if ([string]::IsNullOrWhiteSpace([string]$builtExe) -or -not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
    throw "Pake reported success but no standalone Windows EXE could be located."
}

Write-Host ""
Write-Host "Standalone EXE:" -ForegroundColor Green
Write-Host "  $builtExe"

& (Join-Path $KitRoot "scripts\Assemble-Pake-Portable.ps1") `
    -SourceRoot $SourceRoot `
    -KitRoot $KitRoot `
    -OutputRoot $OutputRoot `
    -BuiltExe $builtExe `
    -AppName $Name `
    -Url $Url

# Pake may update Cargo.lock while generating a packaged app.
git -C $SourceRoot checkout -- src-tauri/Cargo.lock 2>$null
