# Node orchestrator (VDS agent)

Small HTTP service that runs on the same Ubuntu host as Docker and executes `docker run` for GoonStrike dedicated containers. The FastAPI backend calls it after minting an enrollment token (`POST /servers/admin/orchestrator/spawn`).

- **Agent code:** `agent/main.py`, build via `agent/Dockerfile`.
- **Deploy / security / API:** see `docs/vds_orchestrator.md`.
- **Dedicated image:** build with `docker build -f orchestrator/dedicated.Dockerfile.example -t goonstrike-dedicated:latest .`.

Agent endpoints (protected by `X-GS-Agent-Token`):

- `POST /v1/instances`
- `GET /v1/instances`
- `GET /v1/instances/{port}`
- `GET /v1/instances/{port}/logs?tail=200`
- `DELETE /v1/instances/{port}`
