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
set "REGISTRY_KEY_ID="
set "REGISTRY_SECRET="

if not "%~1"=="" set "PORT=%~1"
if not "%~2"=="" set "MAP=%~2"
if not "%~3"=="" set "MODE=%~3"
if not "%~4"=="" set "BACKEND_URL=%~4"
if not "%~5"=="" set "REGISTRY_KEY_ID=%~5"
if not "%~6"=="" set "REGISTRY_SECRET=%~6"

echo.
echo Starting GoonStrike dedicated server...
echo Port: %PORT%
echo Map: %MAP%
echo Mode: %MODE%
if "%BACKEND_URL%"=="" (
    echo Backend: disabled
) else (
    echo Backend: %BACKEND_URL%
    if "%REGISTRY_KEY_ID%"=="" (
        echo Registry auth: disabled (missing key id)
    ) else (
        echo Registry key id: %REGISTRY_KEY_ID%
    )
)
echo.

if "%BACKEND_URL%"=="" (
    godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE%
) else (
    if "%REGISTRY_KEY_ID%"=="" (
        godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE% --backend-url %BACKEND_URL%
    ) else (
        if "%REGISTRY_SECRET%"=="" (
            godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE% --backend-url %BACKEND_URL% --registry-key-id %REGISTRY_KEY_ID%
        ) else (
            godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port %PORT% --map %MAP% --mode %MODE% --backend-url %BACKEND_URL% --registry-key-id %REGISTRY_KEY_ID% --registry-secret %REGISTRY_SECRET%
        )
    )
)

echo.
echo Dedicated server stopped.
pause
exit /b 0

:help
echo Usage:
echo   start_dedicated_server.bat [port] [map] [mode] [backend_url] [registry_key_id] [registry_secret]
echo.
echo Examples:
echo   start_dedicated_server.bat
echo   start_dedicated_server.bat 7000 default team_elim http://127.0.0.1:8000
echo   start_dedicated_server.bat 7001 default dm http://127.0.0.1:8000 dev-key dev-secret
echo.
echo Note:
echo   This script starts only the Godot dedicated server.
echo   Backend is optional. Run start_backend.bat and pass backend_url only if persistence is needed.
echo   For protected registry, pass registry_key_id and registry_secret or set GOONSTRIKE_REGISTRY_SECRET.
exit /b 0
