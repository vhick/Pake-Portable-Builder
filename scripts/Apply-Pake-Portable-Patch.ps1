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

    # GitHub's Windows checkout may produce CRLF, while our patch template uses LF.
    # Normalize before matching so identical Rust source does not fail purely because
    # of line endings.
    return $Text.Replace("`r`n","`n").Replace("`r","`n")
}

function Replace-ExactNormalized {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )

    $Text = Normalize-Newlines $Text
    $Old = Normalize-Newlines $Old
    $New = Normalize-Newlines $New

    if ($Text.Contains($New)) {
        Write-Host "$Label already present." -ForegroundColor DarkGray
        return $Text
    }

    if (-not $Text.Contains($Old)) {
        throw "Could not apply '$Label'. The expected source text was not found after normalizing line endings. Upstream Pake may have changed."
    }

    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $Text.Replace($Old,$New)
}

function Replace-OneRegex {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )

    $Text = Normalize-Newlines $Text
    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $matches = $regex.Matches($Text)

    if ($matches.Count -ne 1) {
        Write-Host ""
        Write-Host "Patch diagnostic for: $Label" -ForegroundColor Yellow
        Write-Host "Expected exactly one match; found $($matches.Count)." -ForegroundColor Yellow
        Write-Host ""

        # Show the current get_data_dir area when possible, making future GitHub
        # logs useful without requiring another inspection workflow first.
        $start = $Text.IndexOf("pub fn get_data_dir")
        if ($start -ge 0) {
            $length = [Math]::Min(1800, $Text.Length - $start)
            Write-Host $Text.Substring($start,$length)
        }

        throw "Could not apply '$Label'. Upstream Pake may have changed. Failing closed instead of producing a possibly non-portable build."
    }

    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $regex.Replace($Text,$Replacement,1)
}

# -------------------------------------------------------------------
# 1. Redirect Pake's EXPLICIT WebView profile.
#
# Pake currently calls:
#   app.path().config_dir()?.join(package_name)
# and then passes that path to WebviewWindowBuilder.data_directory(...).
#
# Tauri explicitly documents that appDirectoriesOverride does NOT override
# a window's explicit dataDirectory, so this function must be patched too.
# -------------------------------------------------------------------

$util = Normalize-Newlines (Get-Content -LiteralPath $utilFile -Raw)

if ($util.Contains('.join("Data")') -and $util.Contains('.join("WebView")')) {
    Write-Host "WebView path patch already present." -ForegroundColor DarkGray
}
else {
    foreach ($required in @(
        "pub fn get_data_dir",
        ".path()",
        ".config_dir()",
        ".join(package_name)"
    )) {
        if ($util.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
            throw "Pake get_data_dir changed upstream: missing '$required'. Re-inspection is required."
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

    # Match the complete current get_data_dir function through the closing brace
    # immediately before show_toast. This is insensitive to CRLF/LF and harmless
    # formatting changes inside the function.
    $pattern = '(?ms)^pub fn get_data_dir\(app:\s*&AppHandle,\s*package_name:\s*String\)\s*->\s*std::io::Result<PathBuf>\s*\{.*?^\}\s*(?=pub fn show_toast)'

    $util = Replace-OneRegex `
        -Text $util `
        -Pattern $pattern `
        -Replacement ((Normalize-Newlines $newDataDir) + "`n") `
        -Label "redirect explicit WebView data directory"
}

Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8 -NoNewline

# -------------------------------------------------------------------
# 2. Redirect Tauri/plugin app_* directories to Data\App.
#
# Tauri documents runtime mutation of generate_context!() as a supported way
# to set AppDirectoriesOverride. Keep this separate from the WebView patch
# because Pake explicitly configures its WebView data directory.
# -------------------------------------------------------------------

$lib = Normalize-Newlines (Get-Content -LiteralPath $libFile -Raw)

$oldConfigLine = '    let (pake_config, tauri_config) = get_pake_config();'

$newConfigBlock = @'
    let (pake_config, tauri_config) = get_pake_config();

    // PAKE_TRUE_PORTABLE_V1
    // Keep Tauri/plugin data in a dedicated subfolder beside the portable EXE.
    // Pake's explicit WebView dataDirectory is redirected separately in util.rs.
    let mut portable_context = tauri::generate_context!();
    #[cfg(target_os = "windows")]
    {
        use tauri::utils::config::AppDirectoriesOverride;
        portable_context.config_mut().app.app_directories_override =
            Some(AppDirectoriesOverride::Root("./Data/App".into()));
    }
'@

$lib = Replace-ExactNormalized `
    -Text $lib `
    -Old $oldConfigLine `
    -New $newConfigBlock `
    -Label "create portable Tauri context"

$lib = Replace-ExactNormalized `
    -Text $lib `
    -Old '        .build(tauri::generate_context!())' `
    -New '        .build(portable_context)' `
    -Label "build with portable Tauri context"

Set-Content -LiteralPath $libFile -Value $lib -Encoding UTF8 -NoNewline

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "1.1"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_app_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    downloads = "normal Windows Downloads directory"
    patch_matching = "CRLF/LF-safe"
    notes = @(
        "Tauri/plugin app directories are redirected at runtime.",
        "Pake's explicit WebView dataDirectory is redirected separately.",
        "Downloads intentionally remain in the normal Windows Downloads folder."
    )
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake true-portable source patch applied successfully." -ForegroundColor Green
Write-Host "  Tauri/plugin data: .\Data\App" -ForegroundColor Green
Write-Host "  WebView data:      .\Data\WebView\<AppName>" -ForegroundColor Green
