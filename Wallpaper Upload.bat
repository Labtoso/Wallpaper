@echo off
setlocal DisableDelayedExpansion
if /i "%~1"=="--self-test" goto SelfTest
if not exist "%~dp0uploader\Wallpaper-Upload.ps1" (
  echo Der Unterordner uploader fehlt. Bitte das gesamte portable Paket entpacken.
  pause
  exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0uploader\Wallpaper-Upload.ps1"
exit /b 0
:SelfTest
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0uploader\Wallpaper-Upload.ps1" -SelfTest
exit /b %errorlevel%
