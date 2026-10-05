# Pake True-Portable Builder

This repository creates portable Windows apps from your clean synchronized `Pake` fork.

## Build modes

- `one-off` — enter a URL/name in the GitHub Actions form.
- `rebuild-saved` — builds every enabled JSON file under `apps/`.
- `inspect-source` — collects relevant upstream source if a future Pake update breaks the patch.

## Portable storage

The source patch redirects:

- Tauri/plugin app data → `.\Data\App`
- Pake's explicit WebView data directory → `.\Data\WebView\<AppName>`

Downloads remain in the normal Windows Downloads folder.

## Why both patches are needed

Pake explicitly calls `WebviewWindowBuilder.data_directory(...)`.
Tauri's application directory override does not override an explicitly configured WebView data directory.

## Windows output

The builder uses Pake's supported `--keep-binary` option and packages the raw Windows EXE rather than asking you to install the generated MSI.

## Automatic rebuilding

Save app definitions under `apps/*.json`.

When your Universal Fork Sync sees a new Pake commit, it can trigger this repository in `rebuild-saved` mode.
