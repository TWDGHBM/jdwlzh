@echo off
cd /d "%~dp0"
echo ============================================
echo  LoneWolf Chinese Patch v2.3 - uninstall
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_delta.ps1"
echo.
echo ExitCode=%errorlevel%
pause