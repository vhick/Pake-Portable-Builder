SAVED PAKE APPS — WINDOWS FEATURE TEMPLATE
==========================================

The GitHub "Run workflow" form is limited to 25 inputs, so the most useful
Windows options are shown interactively there.

For the COMPLETE Windows option set, use an enabled JSON file under apps/.

Start from:
  apps\_EXAMPLE.json

IMPORTANT HOTKEY SETTING
------------------------
Keep:

  "disabledWebShortcuts": false

if you want Pake's built-in Windows web shortcuts to remain enabled.

Current Pake documents shortcuts including:
  Ctrl+Left / Ctrl+Right  back / forward
  Ctrl+R                  reload
  Ctrl+- / Ctrl+= / Ctrl+0 zoom
  Ctrl+Shift+H            home
  F11                     fullscreen
  Ctrl+F / Ctrl+G         Find UI when enableFind=true

WINDOW-FOCUSED OPTIONS
----------------------
Sizing:
  width
  height
  minWidth
  minHeight
  zoom

Window:
  hideWindowDecorations
  fullscreen
  maximize
  alwaysOnTop
  activationShortcut
  title

Tray:
  showSystemTray
  systemTrayIcon
  hideOnClose
  startToTray

Navigation:
  forceInternalNavigation
  internalUrlRegex
  safeDomain
  newWindow
  multiWindow
  multiInstance

WebView:
  incognito
  enableFind
  disabledWebShortcuts
  darkMode
  userAgent
  wasm
  enableDragDrop
  proxyUrl
  debug
  ignoreCertificateErrors

Build:
  targets          x64 or arm64
  appVersion

AUTOMATIC REBUILD
-----------------
Set:

  "enabled": true

for every app you want rebuilt automatically when your synchronized Pake fork
receives a new upstream commit.


CONFIG-BASED BUILD ENGINE
-------------------------
This pack no longer assembles a very long Pake command line.

It generates a temporary JSON config and runs:

  pake --config <generated-file> --json

This uses Pake's published configuration schema and gives much cleaner error
messages for automation.

`targets` now defaults to an empty string in saved app definitions. Empty means
Pake auto-detects the native Windows architecture. Set it to `x64` or `arm64`
only when you specifically want to force that target.
