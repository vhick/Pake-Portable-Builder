# Pake True-Portable Builder — Final Working Pack

This repository creates portable Windows apps from your clean synchronized `Pake` fork.

## Build modes

- `one-off` — manually enter a website URL and app name in GitHub Actions.
- `rebuild-saved` — build every enabled JSON definition under `apps/`.
- `inspect-storage` — collect pristine Pake storage-path source for troubleshooting future upstream changes.

## Portable storage

The working source patch redirects:

- Tauri/plugin app data → `.\Data\App`
- Pake's explicit WebView profile → `.\Data\WebView\<AppName>`

Pake's WebView path must be handled separately because Pake explicitly supplies a WebView `data_directory`.

Downloads intentionally remain in the normal Windows Downloads folder.

## Windows output

The builder uses Pake's supported `--keep-binary` option and packages the standalone Windows executable rather than requiring the generated MSI to be installed.

## Saved apps / automatic rebuilding

Create enabled JSON definitions under `apps/`.

When Universal Fork Sync detects a new commit in your clean `Pake` fork, it triggers this builder with:

`mode = rebuild-saved`

Only JSON files with `"enabled": true` are rebuilt.

## Failure diagnostics

If a build fails, the workflow automatically uploads:

`Pake-Portable-FAILURE-Diagnostics-<commit>`

For storage-layout changes, manually run:

`mode = inspect-storage`

and download:

`Pake-Storage-Inspection-<commit>`

## Important repository design

Keep your `Pake` fork clean.

All portability logic belongs in this separate `Pake-Portable-Builder` repository.


## Windows feature parity

The builder now passes the current Windows-relevant Pake CLI features through
`Build-One-PakeApp.ps1`.

The manual GitHub form exposes the highest-value window controls because GitHub
limits `workflow_dispatch` to 25 inputs.

Saved `apps/*.json` definitions expose the larger Windows feature set, including
window sizing/zoom, activation shortcut, frameless window, fullscreen/maximize,
always-on-top, navigation policy, popup/multi-window behavior, user-agent,
WebAssembly, drag/drop, proxy, debug mode and certificate-error handling.

`disabledWebShortcuts` defaults to `false`, so Pake's built-in Windows keyboard
shortcuts remain enabled unless you deliberately turn them off.

Pake's native navigation/zoom/window application menu is upstream macOS-only.
This builder does not pretend to add that unsupported native menu to Windows;
Windows uses Pake's hotkeys, tray behavior and window controls instead.
