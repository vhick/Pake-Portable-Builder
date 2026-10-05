SAVED PAKE APPS
===============

Why this folder exists
----------------------
A one-off app is built only when you manually run the workflow.

If you want an app to rebuild automatically whenever your Pake fork updates,
create an enabled JSON file here.

Example:

  apps\ChatGPT.json

Contents:

{
  "enabled": true,
  "url": "https://chatgpt.com",
  "name": "ChatGPT",
  "icon": "",
  "width": 1200,
  "height": 780,
  "showSystemTray": true,
  "hideOnClose": true,
  "startToTray": false,
  "incognito": false,
  "enableFind": true,
  "darkMode": false
}

You can keep multiple enabled JSON files.

When Universal Fork Sync detects a new Pake commit, it triggers:

  Pake-Portable-Builder
  mode = rebuild-saved

and every enabled JSON app is rebuilt.

The included _EXAMPLE.json is disabled and is only a template.
