param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$KitRoot,
    [Parameter(Mandatory=$true)][string]$AppsRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)

$ErrorActionPreference = "Stop"

function Get-Value {
    param($Object,[string]$Name,$Default)
    if ($null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $Default
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$configs = @(
    Get-ChildItem -LiteralPath $AppsRoot -Filter "*.json" -File -ErrorAction SilentlyContinue |
    Sort-Object Name
)

$built = 0

foreach ($file in $configs) {
    $cfg = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json

    if (-not [bool](Get-Value $cfg "enabled" $false)) {
        Write-Host "Skipping disabled config: $($file.Name)" -ForegroundColor DarkGray
        continue
    }

    $name = [string](Get-Value $cfg "name" "")
    $url = [string](Get-Value $cfg "url" "")

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($url)) {
        throw "Saved config $($file.Name) must contain name and url."
    }

    & (Join-Path $KitRoot "scripts\Build-One-PakeApp.ps1") `
        -SourceRoot $SourceRoot `
        -KitRoot $KitRoot `
        -OutputRoot $OutputRoot `
        -Url $url `
        -Name $name `
        -Icon ([string](Get-Value $cfg "icon" "")) `
        -Width ([int](Get-Value $cfg "width" 1200)) `
        -Height ([int](Get-Value $cfg "height" 780)) `
        -MinWidth ([int](Get-Value $cfg "minWidth" 0)) `
        -MinHeight ([int](Get-Value $cfg "minHeight" 0)) `
        -Zoom ([int](Get-Value $cfg "zoom" 100)) `
        -ShowSystemTray ([bool](Get-Value $cfg "showSystemTray" $true)) `
        -HideOnClose ([bool](Get-Value $cfg "hideOnClose" $true)) `
        -StartToTray ([bool](Get-Value $cfg "startToTray" $false)) `
        -Incognito ([bool](Get-Value $cfg "incognito" $false)) `
        -EnableFind ([bool](Get-Value $cfg "enableFind" $true)) `
        -DarkMode ([bool](Get-Value $cfg "darkMode" $false)) `
        -HideWindowDecorations ([bool](Get-Value $cfg "hideWindowDecorations" $false)) `
        -Fullscreen ([bool](Get-Value $cfg "fullscreen" $false)) `
        -Maximize ([bool](Get-Value $cfg "maximize" $false)) `
        -ActivationShortcut ([string](Get-Value $cfg "activationShortcut" "")) `
        -AlwaysOnTop ([bool](Get-Value $cfg "alwaysOnTop" $false)) `
        -ForceInternalNavigation ([bool](Get-Value $cfg "forceInternalNavigation" $false)) `
        -MultiWindow ([bool](Get-Value $cfg "multiWindow" $false)) `
        -NewWindow ([bool](Get-Value $cfg "newWindow" $false)) `
        -Title ([string](Get-Value $cfg "title" "")) `
        -DisabledWebShortcuts ([bool](Get-Value $cfg "disabledWebShortcuts" $false)) `
        -InternalUrlRegex ([string](Get-Value $cfg "internalUrlRegex" "")) `
        -SafeDomain ([string](Get-Value $cfg "safeDomain" "")) `
        -UserAgent ([string](Get-Value $cfg "userAgent" "")) `
        -SystemTrayIcon ([string](Get-Value $cfg "systemTrayIcon" "")) `
        -Wasm ([bool](Get-Value $cfg "wasm" $false)) `
        -EnableDragDrop ([bool](Get-Value $cfg "enableDragDrop" $false)) `
        -MultiInstance ([bool](Get-Value $cfg "multiInstance" $false)) `
        -ProxyUrl ([string](Get-Value $cfg "proxyUrl" "")) `
        -Debug ([bool](Get-Value $cfg "debug" $false)) `
        -IgnoreCertificateErrors ([bool](Get-Value $cfg "ignoreCertificateErrors" $false)) `
        -Targets ([string](Get-Value $cfg "targets" "x64")) `
        -AppVersion ([string](Get-Value $cfg "appVersion" ""))

    $built++
}

if ($built -eq 0) {
    Set-Content -LiteralPath (Join-Path $OutputRoot "NO-SAVED-APPS.txt") `
        -Encoding UTF8 `
        -Value @(
            "No enabled saved Pake apps were found.",
            "",
            "Add one or more enabled .json files under the builder repository's apps folder.",
            "See apps\_EXAMPLE.json."
        )

    Write-Host "No enabled saved apps. Nothing to rebuild." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "Built $built saved portable Pake app(s)." -ForegroundColor Green
}
