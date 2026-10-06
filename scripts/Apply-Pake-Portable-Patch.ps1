param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

$utilFile = Join-Path $SourceRoot "src-tauri\src\util.rs"
$libFile = Join-Path $SourceRoot "src-tauri\src\lib.rs"

foreach ($file in @($utilFile,$libFile)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Expected Pake source file was not found: $file"
    }
}

function Normalize-Newlines {
    param([string]$Text)
    return $Text.Replace("`r`n","`n").Replace("`r","`n")
}

function Require-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Label
    )

    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) {
        throw "$Label is missing expected source: $Needle"
    }
}

$util = Normalize-Newlines (Get-Content -LiteralPath $utilFile -Raw)

foreach ($helper in @(
    "pub fn read_last_url",
    "pub fn write_last_url",
    "pub fn get_download_dir",
    "fn expand_download_dir"
)) {
    Require-Contains -Text $util -Needle $helper -Label "Pre-patch util.rs safety check"
}

if ($util.Contains("PAKE_PORTABLE_WEBVIEW_V3")) {
    Write-Host "Portable WebView patch already present." -ForegroundColor DarkGray
}
else {
    $oldDataExpression = @'
    let data_dir = app
        .path()
        .config_dir()
        .map_err(|err| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("Failed to resolve config dir: {err}"),
            )
        })?
        .join(package_name);
'@

    $newDataExpression = @'
    // PAKE_PORTABLE_WEBVIEW_V3
    let data_dir = if cfg!(target_os = "windows") {
        let executable = std::env::current_exe().map_err(|err| {
            std::io::Error::new(
                err.kind(),
                format!("Failed to resolve portable executable path: {err}"),
            )
        })?;

        let executable_dir = executable.parent().ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Portable executable has no parent directory",
            )
        })?;

        executable_dir
            .join("Data")
            .join("WebView")
            .join(package_name)
    } else {
        app.path()
            .config_dir()
            .map_err(|err| {
                std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    format!("Failed to resolve config dir: {err}"),
                )
            })?
            .join(package_name)
    };
'@

    $oldDataExpression = Normalize-Newlines $oldDataExpression
    $newDataExpression = Normalize-Newlines $newDataExpression

    $count = ([regex]::Matches(
        $util,
        [regex]::Escape($oldDataExpression)
    )).Count

    if ($count -ne 1) {
        throw "Expected exactly one original get_data_dir storage expression; found $count. Run inspect-storage before changing the patch."
    }

    $util = $util.Replace($oldDataExpression,$newDataExpression)
    Write-Host "Applied minimal WebView storage redirect." -ForegroundColor Green
}

foreach ($helper in @(
    "pub fn read_last_url",
    "pub fn write_last_url",
    "pub fn get_download_dir",
    "fn expand_download_dir"
)) {
    Require-Contains -Text $util -Needle $helper -Label "Post-patch util.rs safety check"
}

Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8 -NoNewline

$lib = Normalize-Newlines (Get-Content -LiteralPath $libFile -Raw)

Require-Contains -Text $lib -Needle "let mut context = tauri::generate_context!();" -Label "Pake context check"
Require-Contains -Text $lib -Needle ".build(context)" -Label "Pake context consumer check"

if ($lib.Contains("PAKE_TRUE_PORTABLE_CONTEXT_V3")) {
    Write-Host "Portable Tauri context override already present." -ForegroundColor DarkGray
}
else {
    $anchor = "    let mut context = tauri::generate_context!();"

    $portableOverride = @'
    let mut context = tauri::generate_context!();

    // PAKE_TRUE_PORTABLE_CONTEXT_V3
    // Tauri/plugin app_* directories resolve below this dedicated portable root.
    // The explicit WebView profile is handled independently in util.rs.
    #[cfg(target_os = "windows")]
    {
        use tauri::utils::config::AppDirectoriesOverride;
        context.config_mut().app.app_directories_override =
            Some(AppDirectoriesOverride::Root("./Data/App".into()));
    }
'@

    $portableOverride = Normalize-Newlines $portableOverride

    $count = ([regex]::Matches(
        $lib,
        [regex]::Escape($anchor)
    )).Count

    if ($count -ne 1) {
        throw "Expected exactly one mutable Tauri context anchor; found $count. Run inspect-storage."
    }

    $lib = $lib.Replace($anchor,$portableOverride)
    Write-Host "Applied portable Tauri/plugin storage override." -ForegroundColor Green
}

Set-Content -LiteralPath $libFile -Value $lib -Encoding UTF8 -NoNewline

$utilCheck = Get-Content -LiteralPath $utilFile -Raw
$libCheck = Get-Content -LiteralPath $libFile -Raw

foreach ($needle in @(
    "PAKE_PORTABLE_WEBVIEW_V3",
    '.join("Data")',
    '.join("WebView")',
    "pub fn read_last_url",
    "pub fn write_last_url",
    "pub fn get_download_dir",
    "fn expand_download_dir"
)) {
    Require-Contains -Text $utilCheck -Needle $needle -Label "util.rs final self-check"
}

foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_CONTEXT_V3",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    ".build(context)"
)) {
    Require-Contains -Text $libCheck -Needle $needle -Label "lib.rs final self-check"
}

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "3.0"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    source_basis = "exact GitHub failure diagnostics for revision 62cb4eb19f79ae66e73f173768a1db94227b7762"
    safety = "minimal expression replacement; adjacent Pake helpers are verified before and after patch"
} |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake portable source patch v3.0 applied successfully." -ForegroundColor Green
