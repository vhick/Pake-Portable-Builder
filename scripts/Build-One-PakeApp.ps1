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
    [bool]$PakeDebug = $false,
    [bool]$IgnoreCertificateErrors = $false,
    [string]$Targets = "",
    [string]$AppVersion = ""
)

$ErrorActionPreference = "Stop"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$KitRoot = [IO.Path]::GetFullPath($KitRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

# -------------------------------------------------------------------
# IMPORTANT v1.3:
# Create diagnostics BEFORE any wrapper/preflight check.
#
# The previous failure artifact had NO .pake-portable-run folder and no
# generated .pake config files. That proves the failure happened before
# Pake itself was launched.
# -------------------------------------------------------------------

$runDir = Join-Path $SourceRoot ".pake-portable-run"

if (Test-Path -LiteralPath $runDir) {
    Remove-Item -LiteralPath $runDir -Recurse -Force
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$configPath = Join-Path $runDir "pake-build-config.json"
$stdoutPath = Join-Path $runDir "pake-stdout.json"
$stderrPath = Join-Path $runDir "pake-stderr.log"
$helpPath = Join-Path $runDir "pake-help.txt"
$stagePath = Join-Path $runDir "stage.txt"
$inputsPath = Join-Path $runDir "builder-inputs.json"

function Set-Stage {
    param([string]$Stage)

    Set-Content -LiteralPath $stagePath -Encoding UTF8 -Value @(
        "Stage: $Stage",
        "Time: $(Get-Date -Format o)"
    )

    Write-Host ""
    Write-Host "Pake portable stage: $Stage" -ForegroundColor Cyan
}

[ordered]@{
    url = $Url
    name = $Name
    icon = $Icon
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
    hideWindowDecorations = $HideWindowDecorations
    fullscreen = $Fullscreen
    maximize = $Maximize
    activationShortcut = $ActivationShortcut
    alwaysOnTop = $AlwaysOnTop
    forceInternalNavigation = $ForceInternalNavigation
    multiWindow = $MultiWindow
    newWindow = $NewWindow
    title = $Title
    disabledWebShortcuts = $DisabledWebShortcuts
    internalUrlRegex = $InternalUrlRegex
    safeDomain = $SafeDomain
    userAgent = $UserAgent
    systemTrayIcon = $SystemTrayIcon
    wasm = $Wasm
    enableDragDrop = $EnableDragDrop
    multiInstance = $MultiInstance
    proxyUrl = $ProxyUrl
    debug = $PakeDebug
    ignoreCertificateErrors = $IgnoreCertificateErrors
    targets = $Targets
    appVersion = $AppVersion
} |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $inputsPath -Encoding UTF8

Set-Stage "wrapper-started"

if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "URL is required."
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    throw "App name is required."
}

# -------------------------------------------------------------------
# Build Pake's official declarative config.
#
# Deliberately do NOT duplicate Pake's own schema validation here.
# Pake already validates unknown fields, types, ranges and unsupported
# combinations. Duplicating that logic in PowerShell caused the last
# failure before the CLI was even launched.
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
    debug = $PakeDebug
    ignoreCertificateErrors = $IgnoreCertificateErrors

    # Keep the raw Windows executable for our portable package.
    keepBinary = $true
}

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

$config |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $configPath -Encoding UTF8

Set-Stage "config-written"

Write-Host ""
Write-Host "Generated Pake config:" -ForegroundColor Cyan
Get-Content -LiteralPath $configPath | ForEach-Object { Write-Host $_ }

# Capture the exact CLI help before the build.
Push-Location $SourceRoot
try {
    & node "dist/cli.js" --help 2>&1 |
        Out-File -LiteralPath $helpPath -Encoding UTF8
}
finally {
    Pop-Location
}

Set-Stage "cli-help-captured"

# -------------------------------------------------------------------
# Let Pake validate its OWN config and return its OWN structured error.
# -------------------------------------------------------------------

$argumentList = @(
    "dist/cli.js",
    "--config", $configPath,
    "--json"
)

Set-Stage "starting-pake-cli"

$process = Start-Process `
    -FilePath "node" `
    -ArgumentList $argumentList `
    -WorkingDirectory $SourceRoot `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

Set-Stage "pake-cli-finished"

$stderrText = ""
if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $stderrText = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Write-Host ""
        Write-Host "Pake stderr/build log:" -ForegroundColor DarkGray
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
        Write-Host ""
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
    elseif (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        $firstUseful = @(
            $stderrText -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 8
        ) -join " | "

        if ($firstUseful) {
            $details += " Stderr: $firstUseful"
        }
    }

    throw $details
}

if ($null -ne $result -and $result.PSObject.Properties.Name -contains "ok") {
    if (-not [bool]$result.ok) {
        throw "Pake returned ok=false even though the process exit code was zero."
    }
}

Set-Stage "pake-build-succeeded"

# -------------------------------------------------------------------
# Locate the raw EXE produced by keepBinary=true.
# -------------------------------------------------------------------

$builtExe = Join-Path $SourceRoot "$Name.exe"

if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
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

    $builtExe = @(
        $candidates |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    ).FullName
}

if (
    [string]::IsNullOrWhiteSpace([string]$builtExe) -or
    -not (Test-Path -LiteralPath $builtExe -PathType Leaf)
) {
    throw "Pake reported success but no standalone Windows EXE could be located."
}

Set-Stage "standalone-exe-found"

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

Set-Stage "portable-package-assembled"

git -C $SourceRoot checkout -- src-tauri/Cargo.lock 2>$null
