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

function Fail-With-Context {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    Write-Host ""
    Write-Host "Patch diagnostic:" -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow

    $idx = $Text.IndexOf($Needle,[StringComparison]::Ordinal)
    if ($idx -ge 0) {
        $from = [Math]::Max(0,$idx - 700)
        $length = [Math]::Min(4200,$Text.Length - $from)
        Write-Host ""
        Write-Host $Text.Substring($from,$length)
    }

    throw $Message
}

# -------------------------------------------------------------------
# 1. Redirect Pake's explicit WebView data directory.
# -------------------------------------------------------------------

$util = Normalize-Newlines (Get-Content -LiteralPath $utilFile -Raw)

if ($util.Contains('.join("Data")') -and $util.Contains('.join("WebView")')) {
    Write-Host "WebView path patch already present." -ForegroundColor DarkGray
}
else {
    foreach ($required in @(
        "pub fn get_data_dir",
        ".config_dir()",
        ".join(package_name)"
    )) {
        if ($util.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
            Fail-With-Context `
                -Text $util `
                -Needle "pub fn get_data_dir" `
                -Message "Pake get_data_dir changed upstream: missing '$required'."
        }
    }

    $start = $util.IndexOf(
        "pub fn get_data_dir",
        [StringComparison]::Ordinal
    )

    $next = $util.IndexOf(
        "pub fn show_toast",
        $start + 1,
        [StringComparison]::Ordinal
    )

    if ($start -lt 0 -or $next -lt 0 -or $next -le $start) {
        Fail-With-Context `
            -Text $util `
            -Needle "pub fn get_data_dir" `
            -Message "Could not determine the get_data_dir function boundaries."
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

    $util =
        $util.Substring(0,$start) +
        (Normalize-Newlines $newDataDir) +
        $util.Substring($next)

    Write-Host "Applying: redirect explicit WebView data directory" -ForegroundColor Cyan
}

Set-Content -LiteralPath $utilFile -Value $util -Encoding UTF8 -NoNewline

# -------------------------------------------------------------------
# 2. Redirect Tauri/plugin data.
#
# v1.5 deliberately DOES NOT use regex for lib.rs.
# The user's logs showed the exact source is present, but regex matching still
# produced false negatives. We now patch by locating the actual source lines.
# -------------------------------------------------------------------

$libText = Normalize-Newlines (Get-Content -LiteralPath $libFile -Raw)

if ($libText.Contains("PAKE_TRUE_PORTABLE_V5")) {
    Write-Host "Portable Tauri context patch already present." -ForegroundColor DarkGray
}
else {
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in ($libText -split "`n",-1)) {
        [void]$lines.Add($line)
    }

    # Find run_app first, so we only modify code inside that function.
    $runAppIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "pub fn run_app() {") {
            $runAppIndex = $i
            break
        }
    }

    if ($runAppIndex -lt 0) {
        Fail-With-Context `
            -Text $libText `
            -Needle "run_app" `
            -Message "Could not find pub fn run_app()."
    }

    # Find the exact get_pake_config assignment by trimmed LINE content.
    $configIndex = -1
    for ($i = $runAppIndex; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "let (pake_config, tauri_config) = get_pake_config();") {
            $configIndex = $i
            break
        }
    }

    if ($configIndex -lt 0) {
        Fail-With-Context `
            -Text $libText `
            -Needle "get_pake_config" `
            -Message "Could not find the get_pake_config assignment inside run_app()."
    }

    $indent = $lines[$configIndex].Substring(
        0,
        $lines[$configIndex].Length - $lines[$configIndex].TrimStart().Length
    )

    $contextLines = @(
        "",
        "${indent}// PAKE_TRUE_PORTABLE_V5",
        "${indent}// Redirect Tauri/plugin app directories for the portable build.",
        "${indent}// Pake's explicit WebView data directory is handled separately in util.rs.",
        "${indent}let mut portable_context = tauri::generate_context!();",
        "",
        "${indent}#[cfg(target_os = `"windows`")]",
        "${indent}{",
        "${indent}    use tauri::utils::config::AppDirectoriesOverride;",
        "${indent}    portable_context.config_mut().app.app_directories_override =",
        "${indent}        Some(AppDirectoriesOverride::Root(`"./Data/App`".into()));",
        "${indent}}"
    )

    for ($offset = 0; $offset -lt $contextLines.Count; $offset++) {
        $lines.Insert($configIndex + 1 + $offset,$contextLines[$offset])
    }

    Write-Host "Applying: create portable Tauri context" -ForegroundColor Cyan

    # Find .build(tauri::generate_context!()) by TRIMMED line content.
    # Current Pake has this as one line. If upstream later splits it over
    # multiple lines, fail with a diagnostic instead of guessing.
    $buildIndex = -1

    for ($i = $configIndex + $contextLines.Count + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq ".build(tauri::generate_context!())") {
            $buildIndex = $i
            break
        }
    }

    if ($buildIndex -lt 0) {
        $currentText = ($lines -join "`n")
        Fail-With-Context `
            -Text $currentText `
            -Needle "generate_context!" `
            -Message "Could not find the Tauri builder .build(tauri::generate_context!()) line."
    }

    $buildIndent = $lines[$buildIndex].Substring(
        0,
        $lines[$buildIndex].Length - $lines[$buildIndex].TrimStart().Length
    )

    $lines[$buildIndex] = "${buildIndent}.build(portable_context)"

    Write-Host "Applying: build with portable Tauri context" -ForegroundColor Cyan

    $libText = $lines -join "`n"
}

Set-Content -LiteralPath $libFile -Value $libText -Encoding UTF8 -NoNewline

# -------------------------------------------------------------------
# 3. Final self-check BEFORE allowing the workflow to continue.
# -------------------------------------------------------------------

$utilCheck = Get-Content -LiteralPath $utilFile -Raw
$libCheck = Get-Content -LiteralPath $libFile -Raw

foreach ($needle in @(
    '.join("Data")',
    '.join("WebView")'
)) {
    if ($utilCheck.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Self-check failed after patching util.rs: missing $needle"
    }
}

foreach ($needle in @(
    "PAKE_TRUE_PORTABLE_V5",
    'AppDirectoriesOverride::Root("./Data/App".into())',
    ".build(portable_context)"
)) {
    if ($libCheck.IndexOf($needle,[StringComparison]::Ordinal) -lt 0) {
        throw "Self-check failed after patching lib.rs: missing $needle"
    }
}

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "Pake Windows true-portable"
    patch_version = "1.5"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    tauri_app_root = "./Data/App"
    webview_root = "./Data/WebView/<productName>"
    downloads = "normal Windows Downloads directory"
    matching = "line-based source editing; no regex for lib.rs"
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".pake-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "Pake true-portable source patch applied successfully." -ForegroundColor Green
Write-Host "  Tauri/plugin data: .\Data\App" -ForegroundColor Green
Write-Host "  WebView data:      .\Data\WebView\<AppName>" -ForegroundColor Green
