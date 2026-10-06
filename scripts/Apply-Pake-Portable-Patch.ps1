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

function Show-Context {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Label
    )

    Write-Host ""
    Write-Host "SOURCE DIAGNOSTIC: $Label" -ForegroundColor Yellow

    $idx = $Text.IndexOf($Needle,[StringComparison]::Ordinal)
    if ($idx -ge 0) {
        $from = [Math]::Max(0,$idx - 900)
        $length = [Math]::Min(5200,$Text.Length - $from)
        Write-Host $Text.Substring($from,$length)
    } else {
        Write-Host "Needle not found: $Needle" -ForegroundColor Yellow
    }

    Write-Host ""
}

# ===================================================================
# A. Pake's explicit WebView data directory
# ===================================================================
#
# Pake explicitly supplies WebviewWindowBuilder.data_directory(...), so
# Tauri's appDirectoriesOverride cannot move this path. Keep this separate.
# ===================================================================

$util = Normalize-Newlines (Get-Content -LiteralPath $utilFile -Raw)

if ($util.Contains('PAKE_PORTABLE_WEBVIEW_V2')) {
    Write-Host "Portable WebView patch already present." -ForegroundColor DarkGray
}
else {
    foreach ($required in @(
        "pub fn get_data_dir",
        ".config_dir()",
        ".join(package_name)"
    )) {
        if ($util.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
            Show-Context -Text $util -Needle "pub fn get_data_dir" -Label "get_data_dir changed"
            throw "Pake get_data_dir no longer has the expected storage behavior. Re-inspection is required."
        }
    }

    $start = $util.IndexOf("pub fn get_data_dir",[StringComparison]::Ordinal)
    $next = $util.IndexOf("pub fn show_toast",$start + 1,[StringComparison]::Ordinal)

    if ($start -lt 0 -or $next -lt 0 -or $next -le $start) {
        Show-Context -Text $util -Needle "pub fn get_data_dir" -Label "get_data_dir boundaries"
        throw "Could not determine get_data_dir function boundaries."
    }

    $newDataDir = @'
// PAKE_PORTABLE_WEBVIEW_V2
pub fn get_data_dir(app: &AppHandle, package_name: String) -> std::io::Result<PathBuf> {
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

    if !data_dir.exists() {
        std::fs::create_dir_all(&data_dir).map_err(|err| {
            std::io::Error::new(
                err.kind(),
                format!("Can't create dir {}: {err}", data_dir.display()),
            )
        })?;
    }

    Ok(data_dir)
}

'@

    $util =
        $util.Substring(0,$start) +
        (Normalize-Newlines $newDataDir) +
        $util.Substring($next)

    Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8 -NoNewline
    Write-Host "Applied portable WebView data path." -ForegroundColor Green
}

# ===================================================================
# B. Tauri/plugin directories
# ===================================================================
#
# IMPORTANT:
# The current Pake source ALREADY creates:
#
#   let mut context = tauri::generate_context!();
#
# and modifies that context for runtime app identity.
#
# Earlier builder versions wrongly tried to create a second context and
# rewrite the Builder call. That was unnecessary and brittle.
#
# v2.0 simply adds appDirectoriesOverride to Pake's EXISTING context.
# No tuple matching. No run_app parsing. No Builder-call replacement.
# ===================================================================

$lib = Normalize-Newlines (Get-Content -LiteralPath $libFile -Raw)

if ($lib.Contains("PAKE_TRUE_PORTABLE_CONTEXT_V2")) {
    Write-Host "Portable Tauri context override already present." -ForegroundColor DarkGray
}
else {
    $anchor = "let mut context = tauri::generate_context!();"
    $anchorIndex = $lib.IndexOf($anchor,[StringComparison]::Ordinal)

    if ($anchorIndex -lt 0) {
        Show-Context -Text $lib -Needle "pub fn run_app" -Label "existing Tauri context not found"
        throw "Current Pake no longer creates a mutable Tauri context in the expected way. Re-inspection is required."
    }

    # Prove that this context is actually consumed by the app builder/run path.
    # Ignore whitespace for this semantic check.
    $compact = [regex]::Replace($lib,'\s+','')

    if (
        $compact.IndexOf(".build(context)",[StringComparison]::Ordinal) -lt 0 -and
        $compact.IndexOf(".run(context)",[StringComparison]::Ordinal) -lt 0
    ) {
        Show-Context -Text $lib -Needle $anchor -Label "context exists but is not consumed"
        throw "Pake creates a mutable context, but this script could not prove that the builder/run path consumes it."
    }

    $insertAt = $anchorIndex + $anchor.Length

    $override = @'

// PAKE_TRUE_PORTABLE_CONTEXT_V2
// Tauri/plugin app directories follow this dedicated portable root.
// Pake's explicit WebView profile is redirected separately in util.rs.
#[cfg(target_os = "windows")]
{
    use tauri::utils::config::AppDirectoriesOverride;
    context.config_mut().app.app_directories_override =
        Some(AppDirectoriesOverride::Root("./Data/App".into()));
}
'@

    $lib =
        $lib.Substring(0,$insertAt) +
        (Normalize-Newlines $override) +
        $lib.Substring($insertAt)

    Set-Content -LiteralPath $libFile -Value $lib -Encoding UTF8 -NoNewline
    Write-Host "Applied portable Tauri/plugin data path to Pake's existing context." -ForegroundColor Green
}

# ===================================================================
# C. Final self-check
# ===================================================================

$utilCheck = Get-Content -LiteralPath $utilFile -Raw
$libCheck = Get-Content -LiteralPath $libFile -Raw

foreach ($needle in @(
    "PAKE_PORTABLE_WEBVIEW_V2",
    '.join("Data")',
    '.join("WebView")'
)) {
    if ($utilCheck.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Post-patch self-check failed in util.rs: missing $needle"
    }
}

foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_CONTEXT_V2",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    "context.config_mut().app.app_directories_override"
)) {
    if ($libCheck.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Post-patch self-check failed in lib.rs: missing $needle"
    }
}

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "2.0"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_app_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    downloads = "normal Windows Downloads directory"
    source_strategy = "reuse Pake's existing mutable Tauri context; no Builder-call rewrite"
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake true-portable source patch v2.0 applied successfully." -ForegroundColor Green
Write-Host "  Tauri/plugin data: .\Data\App" -ForegroundColor Green
Write-Host "  WebView data:      .\Data\WebView\<AppName>" -ForegroundColor Green
