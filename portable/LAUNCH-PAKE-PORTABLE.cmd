@echo off
setlocal EnableExtensions
title __APP_NAME__ Portable

set "ROOT=%~dp0"
set "EXE=%ROOT%__APP_EXE__"
set "DATA=%ROOT%Data"
set "LOGDIR=%ROOT%LauncherLogs"
set "LOG=%LOGDIR%\Launch.log"

if not exist "%DATA%" mkdir "%DATA%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

echo.>>"%LOG%"
echo ==== %date% %time% __APP_NAME__ portable launch ====>>"%LOG%"
echo EXE=%EXE%>>"%LOG%"
echo DATA=%DATA%>>"%LOG%"

if not exist "%EXE%" (
  echo ERROR: %EXE% not found.>>"%LOG%"
  echo.
  echo ERROR: Portable executable was not found.
  pause
  exit /b 1
)

start "" "%EXE%"
exit /b 0
