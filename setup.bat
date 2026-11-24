@echo off
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap\bootstrap.ps1" -ProjectRoot "%~dp0." -Mode server -Action setup %*
set "ZB_EXIT=%ERRORLEVEL%"
if not "%ZB_EXIT%"=="0" echo Dependency check or startup failed. See the message above.
if not defined ZB_NO_PAUSE pause
exit /b %ZB_EXIT%
