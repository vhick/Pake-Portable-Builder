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

function Replace-Required {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )

    if ($Text.Contains($New)) {
        Write-Host "$Label already present." -ForegroundColor DarkGray
        return $Text
    }

    if (-not $Text.Contains($Old)) {
        throw "Could not apply '$Label'. Upstream Pake changed. Failing closed instead of producing a possibly non-portable build."
    }

    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $Text.Replace($Old,$New)
}

# -------------------------------------------------------------------
# 1. Pake explicitly assigns a webview data_directory.
#    Tauri appDirectoriesOverride does NOT override an explicit
#    dataDirectory, so redirect Pake's own get_data_dir on Windows.
# -------------------------------------------------------------------
$util = Get-Content -LiteralPath $utilFile -Raw

$oldDataDir = @'
pub fn get_data_dir(app: &AppHandle, package_name: String) -> std::io::Result<PathBuf> {
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

$newDataDir = @'
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

$util = Replace-Required `
    -Text $util `
    -Old $oldDataDir `
    -New $newDataDir `
    -Label "redirect explicit WebView data directory"

Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8

# -------------------------------------------------------------------
# 2. Redirect all Tauri/plugin app_* directories to Data\App.
#    Do this at runtime so it applies even though Pake generates its own
#    temporary tauri.conf.json for every packaged website.
# -------------------------------------------------------------------
$lib = Get-Content -LiteralPath $libFile -Raw

$oldConfigLine = '    let (pake_config, tauri_config) = get_pake_config();'
$newConfigBlock = @'
    let (pake_config, tauri_config) = get_pake_config();

    // PAKE_TRUE_PORTABLE_V1
    // Keep Tauri/plugin data in a dedicated folder beside the raw portable EXE.
    // Pake's explicit WebView dataDirectory is redirected separately in util.rs.
    let mut portable_context = tauri::generate_context!();
    #[cfg(target_os = "windows")]
    {
        use tauri::utils::config::AppDirectoriesOverride;
        portable_context.config_mut().app.app_directories_override =
            Some(AppDirectoriesOverride::Root("./Data/App".into()));
    }
'@

$lib = Replace-Required `
    -Text $lib `
    -Old $oldConfigLine `
    -New $newConfigBlock `
    -Label "create portable Tauri context"

$lib = Replace-Required `
    -Text $lib `
    -Old '        .build(tauri::generate_context!())' `
    -New '        .build(portable_context)' `
    -Label "build with portable Tauri context"

Set-Content -LiteralPath $libFile -Value $lib -Encoding UTF8

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "1.0"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_app_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    downloads = "normal Windows Downloads directory"
    notes = @(
        "Tauri/plugin app directories are redirected at runtime.",
        "Pake's explicit WebView dataDirectory is redirected separately.",
        "Downloads intentionally remain in the normal Windows Downloads folder."
    )
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake true-portable source patch applied." -ForegroundColor Green
