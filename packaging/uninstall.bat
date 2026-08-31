@echo off
rem ============================================
rem  DSH Agent - Uninstaller
rem  Stops the agent server, removes shortcuts,
rem  then deletes this install directory.
rem  Usage: uninstall.bat [ -y ]
rem    -y   skip confirmation (unattended)
rem ============================================
setlocal EnableDelayedExpansion

echo.
echo ============================================
echo   DSH Agent - Uninstall
echo ============================================
echo.

rem --- 1. Stop the running agent server (port 19999) ---
echo [1/3] Stopping DSH Agent server...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :19999 ^| findstr LISTENING') do (
    echo   Killing process PID %%p
    taskkill /f /pid %%p >nul 2>&1
)
rem ping-based delay: works even when stdin is redirected (timeout.exe does not)
ping -n 3 127.0.0.1 >nul

rem --- 2. Remove desktop shortcut (if any) ---
echo [2/3] Removing shortcuts...
if exist "%USERPROFILE%\Desktop\DSH Agent.lnk" (
    del "%USERPROFILE%\Desktop\DSH Agent.lnk" >nul 2>&1
    echo   Removed desktop shortcut.
)
if exist "%USERPROFILE%\Desktop\DSH Agent\DSH Agent.lnk" (
    rmdir /s /q "%USERPROFILE%\Desktop\DSH Agent" >nul 2>&1
    echo   Removed desktop folder.
)

rem --- 3. Confirm and delete install directory ---
set "CONFIRMED="
if /i "%~1"=="-y" set "CONFIRMED=Y"
if not defined CONFIRMED (
    echo [3/3] Deleting installation files...
    echo.
    set /p answer=  Are you sure you want to uninstall DSH Agent? [Y/N]:
    if /i "!answer!"=="Y" set "CONFIRMED=Y"
)
if not defined CONFIRMED (
    echo.
    echo   Uninstall cancelled. Nothing was removed.
    echo.
    pause
    exit /b 0
)

echo [3/3] Deleting installation files...
set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
echo   Removing: %INSTALL_DIR%

rem Leave this directory first (a directory that is the CWD of a running
rem process cannot be deleted), then launch a detached PowerShell that
rem waits a moment and removes the install folder.
cd /d "%TEMP%"
start "" powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '%INSTALL_DIR%' -Recurse -Force -ErrorAction SilentlyContinue"

echo.
echo   DSH Agent has been uninstalled. This window will close shortly.
ping -n 5 127.0.0.1 >nul
exit /b 0
