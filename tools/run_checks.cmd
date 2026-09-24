@echo off
REM Wrapper for tools\run_headless.ps1.
REM Windows PowerShell 5.1 reads UTF-8 without a BOM as code page 1251, so this
REM file is kept pure ASCII on purpose (same reason as the .ps1 itself).
REM cmd.exe would mangle the Cyrillic in REM lines under the OEM code page, and
REM mojibake in a batch file can swallow the following line.
REM
REM With no arguments every check mode is run. Examples:
REM   tools\run_checks.cmd
REM   tools\run_checks.cmd --prep
REM   tools\run_checks.cmd --prep --validate
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_headless.ps1" %*
exit /b %ERRORLEVEL%
