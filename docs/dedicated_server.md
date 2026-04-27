# Dedicated Server and Backend

GoonStrike now supports a dedicated Godot server process plus a separate FastAPI/PostgreSQL backend for persistent data.

## Architecture

- Godot client: menus, input, HUD, rendering, client-side prediction.
- Godot dedicated server: ENet host, match authority, damage, rounds, money, pickups, game modes.
- FastAPI backend: optional persistent players, accounts, profiles, and long-term stats.
- PostgreSQL: backend database.

Clients must not connect directly to PostgreSQL. The authoritative Godot server may talk to the backend API when persistence is enabled.

The backend is optional for local/offline play. Active match state is never stored in the backend: positions, damage, money, rounds, pickups, teams, and live timers belong to the Godot dedicated server. The backend should store persistent data only, such as accounts, profiles, inventory/cosmetics, long-term stats, and optional finished-match history.

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
godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port 7000 --map default --mode team_elim --backend-url http://127.0.0.1:8000
```

Useful arguments:

- `--port 7000`
- `--max-players 20`
- `--name dedicated`
- `--map default` or `--map res://resources/maps/default.tres`
- `--mode team_elim` or `--mode dm`
- `--backend-url http://127.0.0.1:8000`
- `--auto-start` for quick tests that should skip the lobby and load the match immediately

The server scene is `scenes/server/server_bootstrap.tscn`. It creates an ENet server through `Lobby.create_dedicated_server()`, applies the selected map/mode, optionally configures `BackendClient`, and waits in the lobby by default.

## Local Dedicated From Game

The main menu has a `Локальная игра` button. It starts a local dedicated server process and connects the client to `127.0.0.1:7000`.

This path does not start Docker and does not pass `--backend-url`, so it works as guest/offline local play.

## Dedicated Lobby Flow

The game client no longer creates an in-process local host. Use either the `Локальная игра` button for local dedicated play or start an external dedicated server separately, then connect clients to it.

1. Optionally run `start_backend.bat` if persistence is needed.
2. Run `start_dedicated_server.bat`, or use `Локальная игра` from the main menu.
3. Start the game client normally.
4. Enter the server IP, for local testing usually `127.0.0.1`.
5. Press `Подключиться`.
6. The first joined client becomes lobby leader (`[OP]`).
7. The leader can select map/mode and press `Начать игру`.
8. Other players can wait and chat in the lobby.

Production servers should be launched as standalone headless processes on Linux or in containers.

## Current Backend API

- `GET /health`
- `POST /players/upsert`
- `GET /players/{external_id}/stats`
- `POST /matches`

Godot currently uses placeholder external ids like `peer:2` until real account/auth IDs exist.

## Notes Before Production

- Add real authentication before trusting persistent player identity.
- Replace `Base.metadata.create_all()` with Alembic migrations before schema changes become important.
- Add server process supervision for Linux deployments.
- Add a matchmaking service before dynamically allocating public dedicated servers.
- Keep gameplay authority in Godot; backend should persist results, not decide damage or round state.
