# Smoke-test dedicated Docker image against this repo:
# Tier A - build image, run short-lived container without backend URL; stdout must contain "Dedicated server listening".
# Tier B (optional) - isolated compose project `gsdedtest`: postgres + backend + dedicated-smoke on same network;
#   mint one-time enrollment for server_id compose-smoke-dedicated; assert GET /servers lists it.
# Tier B env: `$env:SMOKE_ENROLL_ADMIN_TOKEN` - same secret as GOONSTRIKE_REGISTRY_ADMIN_TOKEN for backend container.
#
# Tear-down: Tier B runs `compose down -v` for project gsdedtest only (does not remove your normal `goonstrike` stack).

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$ComposeFiles = @("-f", "docker-compose.yml", "-f", "docker-compose.dedicated-smoke.yml")
$SmokeProj = "gsdedtest"

Write-Host "=== Dedicated smoke: Tier A (Enet listens, no registry) ===" -ForegroundColor Cyan
docker build -f orchestrator/dedicated.Dockerfile.example -t goonstrike-dedicated:smoke .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$cname = "gs-ded-tier-a-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
docker run -d --name $cname `
    -e GOONSTRIKE_DEDICATED_PORT=7999 `
    -p 7999:7999/udp `
    goonstrike-dedicated:smoke
try {
    Start-Sleep -Seconds 8
    # docker prints WARN to stderr; with $ErrorActionPreference Stop stderr would throw.
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $logs = (docker logs $cname 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $ErrorActionPreference = $prevEa
    Write-Host "--- container logs excerpt ---"
    ($logs.Split("`n") | Select-Object -Last 45) -join "`n"
    if ($logs -notmatch "Dedicated server listening") {
        throw "Tier A FAILED: expected substring 'Dedicated server listening' in stdout"
    }
    Write-Host "Tier A OK" -ForegroundColor Green
}
finally {
    docker rm -f $cname 2>$null | Out-Null
}

if (-not $env:SMOKE_ENROLL_ADMIN_TOKEN -or ($env:SMOKE_ENROLL_ADMIN_TOKEN.Trim() -eq "")) {
    Write-Host "`nSMOKE_ENROLL_ADMIN_TOKEN not set - skipping Tier B (registry)." -ForegroundColor Yellow
    Write-Host "To run Tier B:"
    Write-Host '  `$env:SMOKE_ENROLL_ADMIN_TOKEN = "<matches GOONSTRIKE_REGISTRY_ADMIN_TOKEN in backend .env>"'
    Write-Host "  .\scripts\docker_dedicated_smoke.ps1"
    exit 0
}

Write-Host "`n=== Dedicated smoke: Tier B (postgres + backend + dedicated + GET /servers) ===" -ForegroundColor Cyan
$portBusy = $false
try {
    $conns = Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue
    if ($conns) { $portBusy = $true }
}
catch {}
if ($portBusy) {
        Write-Host "Port 8000 is already in use - skipping Tier B (stop other services on :8000 or run only Tier A)." -ForegroundColor Yellow
    exit 0
}

docker compose build backend
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$savedComposeProject = [Environment]::GetEnvironmentVariable("COMPOSE_PROJECT_NAME")

try {
    [Environment]::SetEnvironmentVariable("COMPOSE_PROJECT_NAME", $SmokeProj, "Process")

    $env:SMOKE_ENROLL_ADMIN_TOKEN = $env:SMOKE_ENROLL_ADMIN_TOKEN.Trim()

    docker compose @ComposeFiles up -d postgres
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    docker compose @ComposeFiles up -d backend
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $healthy = $false
    for ($i = 0; $i -lt 180; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $healthy = $true ; break }
        }
        catch {}
        Start-Sleep -Milliseconds 650
    }
    if (-not $healthy) { throw "Tier B FAILED: backend not reachable at http://127.0.0.1:8000/health in time" }

    $hAdmin = @{
        "X-GS-Admin-Token" = $env:SMOKE_ENROLL_ADMIN_TOKEN
        "Content-Type"     = "application/json"
    }
    # Lock token to the same dedicated server id the container uses
    $mint = Invoke-RestMethod -Method Post `
        -Uri "http://127.0.0.1:8000/servers/admin/enrollment-tokens" `
        -Headers $hAdmin `
        -Body '{"server_id":"compose-smoke-dedicated"}'
    $tok = [string]$mint.enrollment_token
    if ([string]::IsNullOrWhiteSpace($tok)) {
        throw "Tier B FAILED: enrollment token mint returned empty"
    }
    $env:SMOKE_ENROLL_TOKEN = $tok
    if (-not $env:SMOKE_DEDICATED_PORT) {
        [Environment]::SetEnvironmentVariable("SMOKE_DEDICATED_PORT", "7124", "Process")
    }

    docker compose @ComposeFiles --profile dedicated-smoke up -d dedicated-smoke
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Start-Sleep -Seconds 22
    $svc = docker compose @ComposeFiles --profile dedicated-smoke ps -q dedicated-smoke | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($svc)) {
        Write-Host "`n--- dedicated-smoke stdout (last lines) ---"
        $prevEa = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        docker logs $svc 2>&1 | Select-Object -Last 50 | ForEach-Object { $_ }
        $ErrorActionPreference = $prevEa
    }

    $list = Invoke-RestMethod -Uri "http://127.0.0.1:8000/servers"
    $present = ($list.servers | Where-Object { [string]$_.server_id -eq "compose-smoke-dedicated" } | Measure-Object).Count -gt 0
    if (-not $present) {
        Write-Host "--- dump dedicated-smoke logs ---"
        docker compose @ComposeFiles --profile dedicated-smoke logs dedicated-smoke --tail 140
        throw "Tier B FAILED: compose-smoke-dedicated absent from GET /servers"
    }
    Write-Host "Tier B OK - trusted list contains compose-smoke-dedicated" -ForegroundColor Green
}
catch {
    Write-Host $_ -ForegroundColor Red
    throw
}
finally {
    [Environment]::SetEnvironmentVariable("COMPOSE_PROJECT_NAME", $SmokeProj, "Process")
    docker compose @ComposeFiles --profile dedicated-smoke down -v 2>$null | Out-Null
    if ($null -ne $savedComposeProject -and $savedComposeProject -ne "") {
        [Environment]::SetEnvironmentVariable("COMPOSE_PROJECT_NAME", $savedComposeProject, "Process")
    }
    else {
        [Environment]::SetEnvironmentVariable("COMPOSE_PROJECT_NAME", $null, "Process")
    }
}

Write-Host "`nDone."
