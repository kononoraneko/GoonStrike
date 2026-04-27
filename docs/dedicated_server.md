# Dedicated Server and Backend

GoonStrike now supports a dedicated Godot server process plus a separate FastAPI/PostgreSQL backend for persistent data.

## Architecture

- Godot client: menus, input, HUD, rendering, client-side prediction.
- Godot dedicated server: ENet host, match authority, damage, rounds, money, pickups, game modes.
- FastAPI backend: optional persistent players, accounts, profiles, long-term stats, and trusted server discovery.
- PostgreSQL: backend database.

Clients must not connect directly to PostgreSQL. The authoritative Godot server may talk to the backend API when persistence is enabled.

The backend is optional for local/offline play. Active match state is never stored in the backend: positions, damage, money, rounds, pickups, teams, and live timers belong to the Godot dedicated server. The backend should store persistent data only, such as accounts, profiles, inventory/cosmetics, long-term stats, optional finished-match history, and a lightweight list of trusted dedicated servers for discovery.

## Run Backend Locally

Only needed if you want persistence while testing. Local dedicated play works without this step.

From the repository root:

```powershell
start_backend.bat
```

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

## Run Dedicated Server From Godot CLI

Example from the repository root:

```powershell
start_dedicated_server.bat
```

Equivalent direct command:

```powershell
godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port 7000 --map default --mode team_elim
```

With optional backend persistence:

```powershell
godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port 7000 --map default --mode team_elim --backend-url http://127.0.0.1:8000 --registry-key-id dev-key --registry-secret dev-secret
```

Useful arguments:

- `--port 7000`
- `--max-players 20`
- `--name dedicated`
- `--map default` or `--map res://resources/maps/default.tres`
- `--mode team_elim` or `--mode dm`
- `--backend-url http://127.0.0.1:8000`
- `--server-id my-server-7000`
- `--public-host 203.0.113.10`
- `--display-name "My Server"`
- `--trusted true`
- `--heartbeat-sec 10`
- `--registry-key-id dev-key`
- `--registry-secret dev-secret` (can be set by env `GOONSTRIKE_REGISTRY_SECRET`)
- `--auto-start` for quick tests that should skip the lobby and load the match immediately
- `--auto-op-first` to automatically make the first joined client the lobby leader

The server scene is `scenes/server/server_bootstrap.tscn`. It creates an ENet server through `Lobby.create_dedicated_server()`, applies the selected map/mode, optionally configures `BackendClient`, requests a backend challenge, signs registry payloads, and waits in the lobby by default.

## Trusted Server Browser

Dedicated servers that are launched with `--backend-url` register themselves in the backend registry and send periodic heartbeats. Clients can press `Обновить` in the main menu to fetch trusted online servers, then connect from the list. Manual IP connection remains available when the backend is offline or the list is empty.

Registry endpoints:

- `GET /servers`
- `POST /servers/challenge`
- `POST /servers/register`
- `POST /servers/{server_id}/heartbeat`
- `POST /servers/{server_id}/offline`
- `POST /servers/admin/credentials` (admin-only key provisioning)

Trusted registry writes now use a signed challenge flow:

1. Dedicated server requests `POST /servers/challenge` with `server_id` and `key_id`.
2. Backend returns one-time `nonce` + `challenge` with short TTL.
3. Dedicated server signs canonical request fields and sends headers:
   - `X-GS-Server-Id`, `X-GS-Key-Id`, `X-GS-Nonce`, `X-GS-Challenge`, `X-GS-Signature`.
4. Backend validates signature, key activity, TTL, and replay (nonce/challenge can be used once).

This is stronger than plain token auth, but still a dev implementation. Use secret rotation, strict credential provisioning, and proper secrets management before production. Clients must not trust map/mode/player counts as authoritative gameplay state; those fields are only for display and connection discovery.

Credential provisioning for dev:

1. Set `GOONSTRIKE_REGISTRY_ADMIN_TOKEN` in backend `.env`.
2. Call admin endpoint with header `X-GS-Admin-Token`.
3. Upsert server credential (`server_id`, `key_id`, `secret`, `is_active`).

Example:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/servers/admin/credentials `
  -Headers @{ "X-GS-Admin-Token" = "your-admin-token" } `
  -ContentType "application/json" `
  -Body '{"server_id":"signed-e2e","key_id":"dev-key","secret":"dev-secret","is_active":true}'
```

## Separate Web Admin Panel (MVP)

The repository includes a separate lightweight frontend in `admin-panel/`.

Run it locally (without Docker):

```powershell
cd admin-panel
python -m http.server 5173
```

Then open:

- `http://127.0.0.1:5173`

Or run via Docker Compose from repo root:

```powershell
docker compose up -d admin-panel
```

Then open:

- `http://127.0.0.1:5173`

Panel capabilities:

- set backend URL and admin token;
- create/rotate/deactivate server credentials via `POST /servers/admin/credentials`;
- view current credentials via `GET /servers/admin/credentials`;
- view trusted online servers via `GET /servers`.

If the panel runs on another origin, add it to `GOONSTRIKE_ADMIN_PANEL_ALLOWED_ORIGINS`.

## Local Dedicated From Game

The main menu has a `Локальная игра` button. It starts a local dedicated server process and connects the client to `127.0.0.1:7000`.

This path does not start Docker and does not pass `--backend-url`, so it works as guest/offline local play. It does pass `--auto-op-first`, so the local player can manage the lobby and start the match.

## Dedicated Lobby Flow

The game client no longer creates an in-process local host. Use either the `Локальная игра` button for local dedicated play or start an external dedicated server separately, then connect clients to it.

1. Optionally run `start_backend.bat` if persistence is needed.
2. Run `start_dedicated_server.bat`, or use `Локальная игра` from the main menu.
3. Start the game client normally.
4. Enter the server IP, for local testing usually `127.0.0.1`.
5. Press `Подключиться`.
6. For `Локальная игра`, the first joined client becomes lobby leader (`[OP]`).
7. For a terminal-started dedicated server, OP is not assigned automatically unless the server was started with `--auto-op-first`.
8. The leader can select map/mode and press `Начать игру`.
9. Other players can wait and chat in the lobby.

Production servers should be launched as standalone headless processes on Linux or in containers.

## Current Backend API

- `GET /health`
- `POST /players/upsert`
- `GET /players/{external_id}/stats`
- `POST /matches`
- `GET /servers`
- `POST /servers/challenge`
- `POST /servers/register`
- `POST /servers/{server_id}/heartbeat`
- `POST /servers/{server_id}/offline`

Godot currently uses placeholder external ids like `peer:2` until real account/auth IDs exist.

## Notes Before Production

- Add real authentication before trusting persistent player identity.
- Add credential management UI/ops flow for server key rotation and revocation.
- Replace `Base.metadata.create_all()` with Alembic migrations before schema changes become important.
- Add server process supervision for Linux deployments.
- Add a matchmaking service before dynamically allocating public dedicated servers.
- Keep gameplay authority in Godot; backend should persist results, not decide damage or round state.
