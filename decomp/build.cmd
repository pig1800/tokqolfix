@echo off
rem Delegate to PowerShell so Python is resolved the same way as in the
rem interactive shell (some machines have a malformed cmd.exe PATH entry).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %errorlevel%
