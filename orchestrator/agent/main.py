"""Minimal VDS node agent: starts/stops dedicated Docker containers on this host.

Mount /var/run/docker.sock and set GOONSTRIKE_AGENT_TOKEN. Never expose this service
to the public internet — only your backend (localhost, WireGuard, or private Docker network).
"""

from __future__ import annotations

import json
import os
import re
import secrets
import subprocess
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

AGENT_TOKEN = (
    os.environ.get("GOONSTRIKE_ORCHESTRATOR_SECRET", "").strip()
    or os.environ.get("GOONSTRIKE_AGENT_TOKEN", "").strip()
)
DEFAULT_IMAGE = os.environ.get("GOONSTRIKE_DEFAULT_IMAGE", "goonstrike-dedicated:latest")

app = FastAPI(title="GoonStrike node agent", version="0.1.0")


class InstanceCreate(BaseModel):
    server_id: str = Field(min_length=1, max_length=128)
    port: int = Field(ge=1024, le=65534)
    backend_url: str = Field(min_length=8, max_length=512)
    enrollment_token: str = Field(min_length=16, max_length=512)
    map_id: str = Field(default="default", max_length=128)
    mode_id: str = Field(default="team_elim", max_length=64)
    docker_image: str = Field(min_length=1, max_length=255)
    public_host: str | None = Field(default=None, max_length=255)


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )


def _require_agent_token(x_gs_agent_token: Annotated[str | None, Header(alias="X-GS-Agent-Token")] = None) -> None:
    if AGENT_TOKEN == "":
        raise HTTPException(
            status_code=503,
            detail="Set GOONSTRIKE_ORCHESTRATOR_SECRET (same value as backend) or GOONSTRIKE_AGENT_TOKEN",
        )
    provided = (x_gs_agent_token or "").strip()
    if provided == "" or not secrets.compare_digest(provided, AGENT_TOKEN):
        raise HTTPException(status_code=401, detail="invalid agent token")


def _container_name(port: int) -> str:
    return f"goonstrike-dedicated-{port}"


def _docker_inspect(name: str) -> dict[str, Any] | None:
    r = _run(["docker", "inspect", name])
    if r.returncode != 0:
        return None
    try:
        data = json.loads(r.stdout)
        return data[0] if isinstance(data, list) and data else None
    except json.JSONDecodeError:
        return None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/instances")
def create_instance(payload: InstanceCreate, _: None = Depends(_require_agent_token)) -> dict[str, Any]:
    name = _container_name(payload.port)
    if _docker_inspect(name) is not None:
        raise HTTPException(status_code=409, detail=f"container {name} already exists; remove it first")

    env_pairs = [
        ("GOONSTRIKE_BACKEND_URL", payload.backend_url.rstrip("/")),
        ("GOONSTRIKE_REGISTRY_ENROLL_TOKEN", payload.enrollment_token),
        ("GOONSTRIKE_REGISTRY_ENROLL_FORCE", "1"),
        ("GOONSTRIKE_SERVER_ID", payload.server_id),
        ("GOONSTRIKE_DEDICATED_PORT", str(payload.port)),
        ("GOONSTRIKE_MAP_ID", payload.map_id),
        ("GOONSTRIKE_MODE_ID", payload.mode_id),
        ("GOONSTRIKE_AUTO_START", "1"),
        ("GOONSTRIKE_AUTO_OP_FIRST", "0"),
    ]
    if payload.public_host:
        env_pairs.append(("GOONSTRIKE_PUBLIC_HOST", payload.public_host.strip()))

    cmd: list[str] = [
        "docker",
        "run",
        "-d",
        "--name",
        name,
        "--restart",
        "unless-stopped",
    ]
    for key, val in env_pairs:
        cmd.extend(["-e", f"{key}={val}"])
    # Dedicated must reach Postgres/FastAPI on the host — public IP URLs often fail inside the bridge ("hairpin NAT").
    # With this host mapping, spawn with backend_url http://host.docker.internal:<backend_port>.
    cmd.extend(["--add-host", "host.docker.internal:host-gateway"])
    # Godot ENetMultiplayerPeer uses UDP; plain -p publishes TCP only and clients cannot connect.
    cmd.extend(["-p", f"{payload.port}:{payload.port}/udp"])
    cmd.extend([payload.docker_image])

    proc = _run(cmd)
    if proc.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail={"docker_error": proc.stderr or proc.stdout, "cmd": "docker run ..."},
        )

    container_id = (proc.stdout or "").strip()
    return {
        "container_name": name,
        "container_id": container_id,
        "port": payload.port,
        "server_id": payload.server_id,
        "image": payload.docker_image,
        "status": "created",
    }


@app.delete("/v1/instances/{port}")
def delete_instance(port: int, _: None = Depends(_require_agent_token)) -> dict[str, Any]:
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="invalid port")
    name = _container_name(port)
    if _docker_inspect(name) is None:
        raise HTTPException(status_code=404, detail=f"container {name} not found")
    remove_proc = _run(["docker", "rm", "-f", name])
    if remove_proc.returncode != 0:
        raise HTTPException(status_code=500, detail=remove_proc.stderr or remove_proc.stdout or "docker rm failed")
    return {"removed": name, "port": port}


def _parse_port_from_name(name: str) -> int | None:
    m = re.match(r"^goonstrike-dedicated-(\d+)$", name)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


@app.get("/v1/instances")
def list_instances(_: None = Depends(_require_agent_token)) -> dict[str, Any]:
    proc = _run(
        [
            "docker",
            "ps",
            "-a",
            "--filter",
            "name=goonstrike-dedicated-",
            "--format",
            "{{.Names}}\t{{.Status}}\t{{.Ports}}",
        ]
    )
    rows: list[dict[str, str]] = []
    for ln in (proc.stdout or "").splitlines():
        parts = ln.split("\t", 2)
        if len(parts) >= 2:
            name = parts[0]
            rows.append(
                {
                    "name": name,
                    "status": parts[1],
                    "ports": parts[2] if len(parts) > 2 else "",
                    "port": _parse_port_from_name(name),
                }
            )
    return {"containers": rows}


@app.get("/v1/instances/{port}")
def get_instance(port: int, _: None = Depends(_require_agent_token)) -> dict[str, Any]:
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="invalid port")
    name = _container_name(port)
    item = _docker_inspect(name)
    if item is None:
        raise HTTPException(status_code=404, detail=f"container {name} not found")
    state = item.get("State", {}) if isinstance(item, dict) else {}
    return {
        "name": name,
        "port": port,
        "running": bool(state.get("Running", False)),
        "status": str(state.get("Status", "")),
        "exit_code": int(state.get("ExitCode", 0)),
        "started_at": str(state.get("StartedAt", "")),
        "finished_at": str(state.get("FinishedAt", "")),
    }


@app.get("/v1/instances/{port}/logs")
def get_instance_logs(port: int, tail: int = 200, _: None = Depends(_require_agent_token)) -> dict[str, Any]:
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="invalid port")
    name = _container_name(port)
    if _docker_inspect(name) is None:
        raise HTTPException(status_code=404, detail=f"container {name} not found")
    safe_tail = max(1, min(tail, 2000))
    proc = _run(["docker", "logs", "--tail", str(safe_tail), name])
    if proc.returncode != 0:
        raise HTTPException(status_code=500, detail=proc.stderr or proc.stdout or "docker logs failed")
    merged_logs = ""
    if proc.stdout:
        merged_logs += proc.stdout
    if proc.stderr:
        if merged_logs and not merged_logs.endswith("\n"):
            merged_logs += "\n"
        merged_logs += proc.stderr
    return {
        "name": name,
        "port": port,
        "tail": safe_tail,
        "logs": merged_logs,
    }
