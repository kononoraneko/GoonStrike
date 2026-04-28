#!/usr/bin/env sh
set -eu

if [ -z "${GOONSTRIKE_BACKEND_URL:-}" ]; then
  echo "WARN: GOONSTRIKE_BACKEND_URL is empty. Server will run without backend registry." >&2
fi

if [ -z "${GOONSTRIKE_SERVER_ID:-}" ]; then
  echo "WARN: GOONSTRIKE_SERVER_ID is empty. server_bootstrap will generate an id from name+port." >&2
fi

exec "${GODOT_BIN:-/opt/godot/godot}" --headless --path /opt/goonstrike \
  scenes/server/server_bootstrap.tscn -- --auto-start
