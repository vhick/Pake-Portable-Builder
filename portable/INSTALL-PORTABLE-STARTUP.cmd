@echo off
setlocal EnableExtensions
title __APP_NAME__ Portable Startup Setup

set "ROOT=%~dp0"
set "LAUNCHER=%ROOT%LAUNCH-PAKE-PORTABLE.cmd"
set "DATADIR=%ROOT%Data"
set "VBS=%DATADIR%\Start-__APP_NAME__-Portable-Hidden.vbs"

if not exist "%DATADIR%" mkdir "%DATADIR%"

> "%VBS%" echo Set sh = CreateObject("WScript.Shell")
>>"%VBS%" echo sh.CurrentDirectory = "%ROOT%"
>>"%VBS%" echo sh.Run Chr(34) ^& "%LAUNCHER%" ^& Chr(34), 0, False

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$startup=[Environment]::GetFolderPath('Startup');" ^
  "$lnk=Join-Path $startup '__APP_NAME__-Portable.lnk';" ^
  "$w=New-Object -ComObject WScript.Shell;" ^
  "$s=$w.CreateShortcut($lnk);" ^
  "$s.TargetPath=$env:WINDIR+'\System32\wscript.exe';" ^
  "$s.Arguments='\"%VBS%\"';" ^
  "$s.WorkingDirectory='%ROOT%';" ^
  "$s.Description='__APP_NAME__ Portable';" ^
  "$s.Save();" ^
  "Write-Host ('Created: '+$lnk)"

echo.
echo Portable startup installed.
pause
