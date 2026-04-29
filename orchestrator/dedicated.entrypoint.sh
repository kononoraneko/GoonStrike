#!/usr/bin/env sh
set -eu

if [ -z "${GOONSTRIKE_BACKEND_URL:-}" ]; then
  echo "WARN: GOONSTRIKE_BACKEND_URL is empty. Server will run without backend registry." >&2
fi

if [ -z "${GOONSTRIKE_SERVER_ID:-}" ]; then
  echo "WARN: GOONSTRIKE_SERVER_ID is empty. server_bootstrap will generate an id from name+port." >&2
fi

# Extra args after "--" — only explicit enable loads the match immediately (dev); default = wait in lobby.
EXTRA=""
case "${GOONSTRIKE_AUTO_START:-}" in
  1|true|yes|on) EXTRA="${EXTRA} --auto-start" ;;
esac
case "${GOONSTRIKE_AUTO_OP_FIRST:-}" in
  1|true|yes|on) EXTRA="${EXTRA} --auto-op-first" ;;
esac

# shellcheck disable=SC2086
exec "${GODOT_BIN:-/opt/godot/godot}" --headless --path /opt/goonstrike \
  scenes/server/server_bootstrap.tscn -- ${EXTRA}
