@echo off
cd /d "%~dp0"
echo ============================================
echo  LoneWolf Chinese Patch v2.3 (delta package)
echo  Rebuilding resources.assets: about 10-30 s
echo  Please do NOT close this window.
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_delta.ps1"
echo.
echo ExitCode=%errorlevel%
pause