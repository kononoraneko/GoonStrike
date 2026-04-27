@echo off
setlocal

cd /d "%~dp0"

if /I "%~1"=="help" goto :help
if /I "%~1"=="--help" goto :help
if /I "%~1"=="/?" goto :help

echo Starting GoonStrike backend and PostgreSQL...
docker compose up -d postgres backend
if errorlevel 1 (
    echo Failed to start Docker services.
    pause
    exit /b 1
)

echo.
echo Backend services are starting.
echo Health check: http://127.0.0.1:8000/health
echo Logs: docker compose logs -f backend
pause
exit /b 0

:help
echo Usage:
echo   start_backend.bat
echo.
echo Starts Docker Compose services:
echo   - postgres
echo   - backend
exit /b 0
