@echo off
setlocal

cd /d "%~dp0"

if /I "%~1"=="help" goto :help
if /I "%~1"=="--help" goto :help
if /I "%~1"=="/?" goto :help

set "PORT=7000"
set "MAP=default"
set "MODE=team_elim"
set "BACKEND_URL="

if not "%~1"=="" set "PORT=%~1"
if not "%~2"=="" set "MAP=%~2"
if not "%~3"=="" set "MODE=%~3"
if not "%~4"=="" set "BACKEND_URL=%~4"

echo.
echo Starting GoonStrike dedicated server...
echo Port: %PORT%
echo Map: %MAP%
echo Mode: %MODE%
if "%BACKEND_URL%"=="" (
    echo Backend: disabled
) else (
    echo Backend: %BACKEND_URL%
)
echo.

if "%BACKEND_URL%"=="" (
    godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE%
) else (
    godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE% --backend-url %BACKEND_URL%
)

echo.
echo Dedicated server stopped.
pause
exit /b 0

:help
echo Usage:
echo   start_dedicated_server.bat [port] [map] [mode] [backend_url]
echo.
echo Examples:
echo   start_dedicated_server.bat
echo   start_dedicated_server.bat 7000 default team_elim http://127.0.0.1:8000
echo   start_dedicated_server.bat 7001 default dm http://127.0.0.1:8000
echo.
echo Note:
echo   This script starts only the Godot dedicated server.
echo   Backend is optional. Run start_backend.bat and pass backend_url only if persistence is needed.
exit /b 0
