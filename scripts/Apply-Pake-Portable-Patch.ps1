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

function Show-Diagnostic {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Label
    )

    Write-Host ""
    Write-Host "Patch diagnostic: $Label" -ForegroundColor Yellow

    $start = $Text.IndexOf($Needle,[StringComparison]::Ordinal)

    if ($start -ge 0) {
        $from = [Math]::Max(0,$start - 500)
        $length = [Math]::Min(3200,$Text.Length - $from)
        Write-Host $Text.Substring($from,$length)
    }
    else {
        Write-Host "Diagnostic needle '$Needle' was not found." -ForegroundColor Yellow
    }

    Write-Host ""
}

function Replace-OneRegex {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label,
        [string]$DiagnosticNeedle
    )

    $Text = Normalize-Newlines $Text
    $Replacement = Normalize-Newlines $Replacement

    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $matches = $regex.Matches($Text)

    if ($matches.Count -ne 1) {
        Show-Diagnostic `
            -Text $Text `
            -Needle $DiagnosticNeedle `
            -Label $Label

        throw "Could not apply '$Label'. Expected exactly one source match but found $($matches.Count). Upstream Pake may have changed."
    }

    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $regex.Replace($Text,$Replacement,1)
}

# -------------------------------------------------------------------
# 1. Pake's explicit WebView data directory
# -------------------------------------------------------------------

$util = Normalize-Newlines (Get-Content -LiteralPath $utilFile -Raw)

if ($util.Contains('.join("Data")') -and $util.Contains('.join("WebView")')) {
    Write-Host "WebView path patch already present." -ForegroundColor DarkGray
}
else {
    # Only verify broad semantic anchors. Do NOT require one exact formatted
    # source line; GitHub/formatter/upstream whitespace can differ.
    foreach ($required in @(
        "pub fn get_data_dir",
        ".config_dir()",
        ".join(package_name)"
    )) {
        if ($util.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
            Show-Diagnostic -Text $util -Needle "pub fn get_data_dir" -Label "WebView path precheck"
            throw "Pake get_data_dir changed upstream: missing '$required'."
        }
    }

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

    $utilPattern = '(?ms)^pub fn get_data_dir\s*\(\s*app\s*:\s*&AppHandle\s*,\s*package_name\s*:\s*String\s*\)\s*->\s*std::io::Result\s*<\s*PathBuf\s*>\s*\{.*?^\}\s*(?=pub fn show_toast)'

    $util = Replace-OneRegex `
        -Text $util `
        -Pattern $utilPattern `
        -Replacement ((Normalize-Newlines $newDataDir) + "`n") `
        -Label "redirect explicit WebView data directory" `
        -DiagnosticNeedle "pub fn get_data_dir"
}

Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8 -NoNewline

# -------------------------------------------------------------------
# 2. Tauri/plugin app directories
#
# IMPORTANT v1.4 change:
# The old script performed a strict precheck for the exact text:
#
#   .build(tauri::generate_context!())
#
# before running a whitespace-tolerant regex.
#
# That strict precheck was redundant and is what failed in the user's v1.3
# run. We now rely on bounded syntax patterns directly.
# -------------------------------------------------------------------

$lib = Normalize-Newlines (Get-Content -LiteralPath $libFile -Raw)

if ($lib.Contains("PAKE_TRUE_PORTABLE_V4")) {
    Write-Host "Portable Tauri context patch already present." -ForegroundColor DarkGray
}
else {
    # Broad sanity checks only.
    foreach ($required in @(
        "pub fn run_app()",
        "get_pake_config()",
        "tauri::Builder::default()",
        "tauri::generate_context!"
    )) {
        if ($lib.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
            Show-Diagnostic -Text $lib -Needle "pub fn run_app()" -Label "Tauri context precheck"
            throw "Pake run_app changed upstream: missing '$required'."
        }
    }

    $newConfigBlock = @'
    let (pake_config, tauri_config) = get_pake_config();

    // PAKE_TRUE_PORTABLE_V4
    // Tauri/plugin app_* paths follow this root. Pake's explicit WebView
    // data directory is redirected separately in util.rs.
    let mut portable_context = tauri::generate_context!();

    #[cfg(target_os = "windows")]
    {
        use tauri::utils::config::AppDirectoriesOverride;
        portable_context.config_mut().app.app_directories_override =
            Some(AppDirectoriesOverride::Root("./Data/App".into()));
    }
'@

    # Match only the get_pake_config assignment. Formatting/indentation may vary.
    $configPattern = '(?s)let\s*\(\s*pake_config\s*,\s*tauri_config\s*\)\s*=\s*get_pake_config\s*\(\s*\)\s*;'

    $lib = Replace-OneRegex `
        -Text $lib `
        -Pattern $configPattern `
        -Replacement (Normalize-Newlines $newConfigBlock).TrimEnd() `
        -Label "create portable Tauri context" `
        -DiagnosticNeedle "get_pake_config"

    # Match the builder call regardless of whitespace/newlines.
    $buildPattern = '(?s)\.build\s*\(\s*tauri::generate_context!\s*\(\s*\)\s*\)'

    $lib = Replace-OneRegex `
        -Text $lib `
        -Pattern $buildPattern `
        -Replacement '.build(portable_context)' `
        -Label "build with portable Tauri context" `
        -DiagnosticNeedle ".build("
}

Set-Content -LiteralPath $libFile -Value $lib -Encoding UTF8 -NoNewline

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "1.4"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_app_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    downloads = "normal Windows Downloads directory"
    matching = "semantic prechecks + bounded whitespace-tolerant regex"
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake true-portable source patch applied successfully." -ForegroundColor Green
Write-Host "  Tauri/plugin data: .\Data\App" -ForegroundColor Green
Write-Host "  WebView data:      .\Data\WebView\<AppName>" -ForegroundColor Green
