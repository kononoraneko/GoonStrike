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

Only needed if you want persistence, accounts, or the trusted server list while testing. Local dedicated play works without this step.

Validation is **Docker-first**: use Docker Compose for PostgreSQL and FastAPI. Do not assume a local `python` or `py` on Windows; `start_backend.bat` wraps Compose.

From the repository root (Windows):

```powershell
start_backend.bat
```

Equivalent (any OS, repository root):

```powershell
docker compose up -d postgres backend
```

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

Optional: start the static admin UI (nginx on port 5173) together with the stack:

```powershell
docker compose up -d postgres backend admin-panel
```

## Game client and API base URL

The game client’s `AuthState` autoload (`scripts/autoloads/auth_state.gd`) configures `BackendClient` when it is still empty: first it reads the environment variable **`GOONSTRIKE_CLIENT_BACKEND_URL`** (full origin, **no** path suffix such as `/api` — use e.g. `https://api.example.com` or `http://127.0.0.1:8000`), otherwise it uses the built-in default `http://127.0.0.1:8000`. A **404 Not Found** on login almost always means the client is talking to the wrong host/port or a URL with an extra path segment; check the message shown in-game and `GET {origin}/health` and `GET {origin}/docs` in a browser.

Dedicated servers use **`--backend-url`** / **`GOONSTRIKE_BACKEND_URL`** independently; they do not rely on `AuthState`.

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
- `--registry-enroll-token ...` or env `GOONSTRIKE_REGISTRY_ENROLL_TOKEN` (one-time exchange for keys; requires `--backend-url`)
- `--registry-credentials-path ...` or env `GOONSTRIKE_REGISTRY_CREDENTIALS_PATH` (defaults to `user://goonstrike_dedicated_registry.cfg`)
- `--registry-enroll-force` — run enrollment even if a credentials file already exists
- `--auto-start` for quick tests that should skip the lobby and load the match immediately
- `--auto-op-first` to automatically make the first joined client the lobby leader

**Environment variables** (Docker / systemd when not passing CLI flags): `GOONSTRIKE_BACKEND_URL`, `GOONSTRIKE_SERVER_ID`, `GOONSTRIKE_DEDICATED_PORT` / `PORT`, `GOONSTRIKE_PUBLIC_HOST`, `GOONSTRIKE_MAP_ID`, `GOONSTRIKE_MODE_ID`, plus the registry/enrollment variables listed above. For spawning containers from the backend, see [vds_orchestrator.md](vds_orchestrator.md).

The server scene is `scenes/server/server_bootstrap.tscn`. It creates an ENet server through `Lobby.create_dedicated_server()`, applies the selected map/mode, optionally configures `BackendClient`, requests a backend challenge, signs registry payloads, and waits in the lobby by default.

## Trusted Server Browser

Dedicated servers that are launched with `--backend-url` register themselves in the backend registry and send periodic heartbeats. Clients can press `Обновить` in the main menu to fetch trusted online servers, then connect from the list. Manual IP connection remains available when the backend is offline or the list is empty.

Registry endpoints:

- `GET /servers`
- `POST /servers/challenge`
- `POST /servers/registry/enroll` (dedicated exchanges one-time enrollment token)
- `POST /servers/register`
- `POST /servers/{server_id}/heartbeat`
- `POST /servers/{server_id}/offline`
- `POST /servers/admin/credentials` (admin-only key provisioning)
- `POST /servers/admin/provision` (admin-only: generate triple, secret returned once)
- `POST /servers/admin/enrollment-tokens` (admin-only: mint one-time enrollment token)
- `GET /servers/admin/orchestrator/instances` (admin-only: list containers on VDS agent)
- `GET /servers/admin/orchestrator/instances/{port}` (admin-only: inspect container status)
- `GET /servers/admin/orchestrator/instances/{port}/logs?tail=200` (admin-only: tail logs via backend proxy)

Trusted registry writes now use a signed challenge flow:

1. Dedicated server requests `POST /servers/challenge` with `server_id` and `key_id`.
2. Backend returns one-time `nonce` + `challenge` with short TTL.
3. Dedicated server signs canonical request fields and sends headers:
   - `X-GS-Server-Id`, `X-GS-Key-Id`, `X-GS-Nonce`, `X-GS-Challenge`, `X-GS-Signature`.
4. Backend validates signature, key activity, TTL, and replay (nonce/challenge can be used once).

The server stores a **hash** of the shared secret; the signature is over a canonical string plus the SHA-256 of the request body, using the same derivation as the Godot client in `BackendClient._registry_headers`. Setting **`GOONSTRIKE_REGISTRY_AUTH_REQUIRED=false`** in the backend (dev only) skips verification — never use that in production.

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

### One-click style flows (recommended for deploy)

**A — Quick provision (admin generates keys for you)**

- `POST /servers/admin/provision` with `X-GS-Admin-Token` (optional JSON: `server_id`, `key_id`; omitted fields are auto-generated).
- Response includes plaintext `secret` **once**. Store it in your secret manager / systemd drop-in / container env (`GOONSTRIKE_REGISTRY_SECRET`), then pass `--registry-key-id` / `--registry-secret` (or env) to the dedicated binary as before.

**B — Enrollment token (no manual secret copy onto the machine)**

1. Admin mints a **one-time** token: `POST /servers/admin/enrollment-tokens` (optional `server_id` lock and `ttl_seconds`; defaults: `GOONSTRIKE_REGISTRY_ENROLLMENT_DEFAULT_TTL_SEC` / `_MAX_` in backend config).
2. Start dedicated **once** with `--backend-url`, matching `--server-id`, and `--registry-enroll-token <token>` (or env `GOONSTRIKE_REGISTRY_ENROLL_TOKEN`).
3. The process calls `POST /servers/registry/enroll`, receives `key_id` + `secret`, and saves them under `user://goonstrike_dedicated_registry.cfg` unless you override `--registry-credentials-path` / `GOONSTRIKE_REGISTRY_CREDENTIALS_PATH`.
4. Next restarts omit the enrollment token; credentials load from that file. Use `--registry-enroll-force` to enroll again (consumes a **new** minted token).

The admin panel (`admin-panel/`) exposes **Provision credentials**, **Mint enrollment token**, and **VDS orchestrator** actions (spawn/list/stop + inspect/logs) that wrap these endpoints.

#### Security notes

- **Better than pasting the admin token on the server**: enrollment uses a **short-lived, single-use** bearer that only creates registry signing keys — not full admin API access.
- Still treat enrollment tokens like passwords: **HTTPS only** toward the backend in production, tight firewall, minimal TTL. Anyone who steals a valid unused token could register **their** host only if they also satisfy `server_id` / optional lock — lock to the exact `--server-id` you put in your systemd unit.
- **Secrets at rest**: restrict permissions on the saved credentials file / env files on the dedicated host (`600`, dedicated user).
- **Provisioning** (`/admin/provision`) returns a long-lived registry secret — handle it like an API key (never commit, rotate via panel/API).

## Separate Web Admin Panel (MVP)

The repository includes a separate lightweight frontend in `admin-panel/`.

Run it locally (without Docker):

```powershell
cd admin-panel
python -m http.server 5173
```

Then open:

- `http://127.0.0.1:5173`

Or run via Docker Compose from repo root (serves `admin-panel/` with nginx):

```powershell
docker compose up -d admin-panel
```

Ensure `GOONSTRIKE_REGISTRY_ADMIN_TOKEN` is set in `backend/.env` — without it, admin routes return 403.

Then open:

- `http://127.0.0.1:5173`

Panel capabilities:

- set backend URL and admin token;
- provision auto-generated credentials (`POST /servers/admin/provision`);
- mint enrollment tokens (`POST /servers/admin/enrollment-tokens`);
- spawn / list / stop dedicated containers via the VDS orchestrator (when configured);
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

## Container size optimization (dedicated)

The sample dedicated Dockerfile (`orchestrator/dedicated.Dockerfile.example`) is optimized to reduce image size:

- multi-stage build (download Godot in a builder stage, keep only runtime binary in final image);
- `debian:bookworm-slim` runtime base instead of full Ubuntu image;
- runtime installs only required shared libs (no curl/unzip in final layer);
- keeps `COPY .` in the dedicated image build (with `.dockerignore` filtering) so Godot service files used by headless startup are preserved.

Tip: keep `.dockerignore` strict so heavy non-runtime directories are excluded from context during dedicated image builds.

## Current Backend API (summary)

**Health**

- `GET /health`

**Auth** (`/auth`, Bearer token after login)

- `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`

**Players**

- `POST /players/upsert`
- `GET /players/{external_id}/stats`

**Matches**

- `POST /matches`

**Economy / profile** (inventory, catalog, cases — see `backend/app/routes/economy.py`)

- `GET /profile/me`, `GET /profile/{external_id}`, `GET /catalog`
- `GET /inventory/me`, `GET /inventory/{external_id}`, `POST /inventory/equip`
- `POST /cases/open`, `POST /wallet/grant-dev` (dev)

**Trusted servers** (`/servers`)

- `GET /servers` — public browser list
- `POST /servers/challenge` — issue nonce/challenge for signing
- `POST /servers/registry/enroll` — dedicated exchanges one-time enrollment token for `key_id` + `secret`
- `POST /servers/register`, `POST /servers/{server_id}/heartbeat`, `POST /servers/{server_id}/offline` — signed writes (unless `GOONSTRIKE_REGISTRY_AUTH_REQUIRED=false`)

**Admin** (header `X-GS-Admin-Token` = `GOONSTRIKE_REGISTRY_ADMIN_TOKEN`)

- `POST /servers/admin/provision`, `POST /servers/admin/enrollment-tokens`
- `POST /servers/admin/credentials`, `GET /servers/admin/credentials`
- `POST /servers/admin/orchestrator/spawn`
- `GET /servers/admin/orchestrator/instances`, `GET .../instances/{port}`, `GET .../instances/{port}/logs`, `DELETE .../instances/{port}`

Godot may still use placeholder external ids like `peer:2` when no account is linked; authenticated flows use backend identities from `GET /auth/me` / profile routes.

## Notes Before Production

- Add real authentication before trusting persistent player identity.
- Add credential management UI/ops flow for server key rotation and revocation.
- Harden enrollment and admin routes (rate limits, audit logs) beyond the current dev implementation.
- Replace `Base.metadata.create_all()` with Alembic migrations before schema changes become important.
- Add server process supervision for Linux deployments.
- Add a matchmaking service before dynamically allocating public dedicated servers.
- Keep gameplay authority in Godot; backend should persist results, not decide damage or round state.
