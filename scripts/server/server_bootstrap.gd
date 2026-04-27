extends Node

## Entry point for dedicated/headless server runs.
## Run with a server scene, for example:
## godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port 7000 --map default --mode team_elim

const DEFAULT_PORT := 7000
const DEFAULT_MAX_PLAYERS := 20

var _backend_client: Node
var _heartbeat_timer: Timer
var _server_id := ""
var _public_host := "127.0.0.1"
var _display_name := "dedicated"
var _is_trusted := true
var _registry_key_id := ""
var _registry_secret := ""
var _registry_auth_context: Dictionary = {}
var _registry_challenge_expires_at: int = 0


func _ready() -> void:
	call_deferred("_start_server")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_mark_server_offline()


func _start_server() -> void:
	var args := _parse_args()
	var port := int(args.get("port", DEFAULT_PORT))
	var max_players := int(args.get("max-players", DEFAULT_MAX_PLAYERS))
	var server_name := String(args.get("name", "dedicated"))
	var map_arg := String(args.get("map", ""))
	var mode_id := String(args.get("mode", GameModeCatalog.ID_TEAM_ELIM))
	var backend_url := String(args.get("backend-url", ""))
	var auto_start := _bool_arg(args.get("auto-start", false))
	var auto_op_first := _bool_arg(args.get("auto-op-first", false))
	var heartbeat_sec := float(args.get("heartbeat-sec", 10.0))
	_display_name = String(args.get("display-name", server_name))
	_public_host = String(args.get("public-host", "127.0.0.1"))
	_server_id = String(args.get("server-id", _make_default_server_id(_display_name, port)))
	_is_trusted = _bool_arg(args.get("trusted", true))
	_registry_key_id = _resolve_arg_or_env(args, "registry-key-id", "GOONSTRIKE_REGISTRY_KEY_ID")
	_registry_secret = _resolve_arg_or_env(args, "registry-secret", "GOONSTRIKE_REGISTRY_SECRET")

	_setup_backend_client(backend_url)

	var err := Lobby.create_dedicated_server(port, max_players, server_name, auto_op_first)
	if err != OK:
		push_error("Dedicated server failed to listen on port %d: %d" % [port, err])
		get_tree().quit(err)
		return

	_apply_map_arg(map_arg)
	Lobby.host_set_mode_id(mode_id)

	print("Dedicated server listening on port %d, map=%s, mode=%s" % [
		Lobby.server_port,
		Lobby.selected_map.resource_path if Lobby.selected_map else "<none>",
		Lobby.selected_mode_id,
	])

	if _backend_client != null and _backend_client.has_method("ping_health"):
		_backend_client.call("ping_health")
	await _register_server(heartbeat_sec)

	if auto_start:
		Lobby.start_match_from_selection()
	else:
		if auto_op_first:
			print("Dedicated server is waiting in lobby. First joined client becomes lobby leader.")
		else:
			print("Dedicated server is waiting in lobby. OP is not auto-assigned.")


func _setup_backend_client(backend_url: String) -> void:
	if backend_url.is_empty():
		return
	var autoload_client := get_node_or_null("/root/BackendClient")
	if autoload_client != null:
		_backend_client = autoload_client
		if _backend_client.has_method("configure"):
			_backend_client.call("configure", backend_url)
		return
	var script := load("res://scripts/autoloads/backend_client.gd") as Script
	if script == null:
		push_warning("BackendClient script not found")
		return
	_backend_client = script.new()
	_backend_client.name = "BackendClient"
	add_child(_backend_client)
	if _backend_client.has_method("configure"):
		_backend_client.call("configure", backend_url)


func _register_server(heartbeat_sec: float) -> void:
	if _backend_client == null or not _backend_client.has_method("register_server"):
		return
	var auth_context := await _auth_context_for_registry(true)
	_backend_client.call("register_server", _build_registry_payload(true), auth_context)
	await _send_server_heartbeat()
	if heartbeat_sec <= 0.0:
		return
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = heartbeat_sec
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_send_server_heartbeat)
	add_child(_heartbeat_timer)


func _send_server_heartbeat() -> void:
	if _backend_client == null or not _backend_client.has_method("heartbeat_server"):
		return
	var auth_context := await _auth_context_for_registry(true)
	if _requires_registry_auth() and auth_context.is_empty():
		return
	_backend_client.call("heartbeat_server", _server_id, _build_registry_payload(false), auth_context)


func _mark_server_offline() -> void:
	call_deferred("_mark_server_offline_async")


func _mark_server_offline_async() -> void:
	if _backend_client == null or not _backend_client.has_method("mark_server_offline"):
		return
	var auth_context := await _auth_context_for_registry(true)
	if _requires_registry_auth() and auth_context.is_empty():
		return
	_backend_client.call("mark_server_offline", _server_id, auth_context)


func _build_registry_payload(include_identity: bool) -> Dictionary:
	var payload := {
		"map_id": _current_map_id(),
		"mode_id": Lobby.selected_mode_id,
		"current_players": _current_player_count(),
		"max_players": Lobby.server_max_connections,
	}
	if include_identity:
		payload.merge({
			"server_id": _server_id,
			"display_name": _display_name,
			"host": _public_host,
			"port": Lobby.server_port,
			"is_trusted": _is_trusted,
		})
	return payload


func _current_map_id() -> String:
	if Lobby.selected_map == null:
		return ""
	return String(Lobby.selected_map.id)


func _current_player_count() -> int:
	var count := 0
	for peer_id in Lobby.players.keys():
		if Lobby.is_dedicated_server and int(peer_id) == 1:
			continue
		count += 1
	return count


func _apply_map_arg(map_arg: String) -> void:
	if map_arg.is_empty():
		return
	if map_arg.begins_with("res://"):
		Lobby.host_set_map_by_path(map_arg)
		return
	for map_data in MapsRegistry.load_all_maps():
		if map_data.id == map_arg or map_data.display_name == map_arg:
			Lobby.host_set_map_by_path(map_data.resource_path)
			return
	push_warning("Unknown map '%s', keeping default map" % map_arg)


func _make_default_server_id(server_name: String, port: int) -> String:
	var normalized := server_name.strip_edges().to_lower().replace(" ", "-")
	if normalized.is_empty():
		normalized = "dedicated"
	return "%s-%d" % [normalized, port]


func _bool_arg(value: Variant) -> bool:
	if value is bool:
		return value
	var text := String(value).strip_edges().to_lower()
	return text in ["1", "true", "yes", "on"]


func _resolve_arg_or_env(args: Dictionary, key: String, env_name: String) -> String:
	var arg_value := String(args.get(key, "")).strip_edges()
	if not arg_value.is_empty():
		return arg_value
	return String(OS.get_environment(env_name)).strip_edges()


func _requires_registry_auth() -> bool:
	return not _registry_key_id.is_empty() and not _registry_secret.is_empty()


func _auth_context_for_registry(force_refresh: bool) -> Dictionary:
	if not _requires_registry_auth():
		return {}
	if not _backend_client.has_method("fetch_server_challenge"):
		return {}
	var now := int(Time.get_unix_time_from_system())
	if not force_refresh and not _registry_auth_context.is_empty() and now < _registry_challenge_expires_at - 1:
		return _registry_auth_context

	var challenge_result: Dictionary = await _backend_client.call("fetch_server_challenge", _server_id, _registry_key_id)
	if not challenge_result.get("ok", false):
		push_warning("Registry challenge request failed: %s" % str(challenge_result.get("raw", challenge_result.get("error", ""))))
		_registry_auth_context = {}
		return {}

	var data: Dictionary = challenge_result.get("data", {}) as Dictionary
	var expires_at := String(data.get("expires_at", "")).strip_edges()
	_registry_challenge_expires_at = int(Time.get_unix_time_from_datetime_string(expires_at)) if not expires_at.is_empty() else 0
	_registry_auth_context = {
		"server_id": _server_id,
		"key_id": _registry_key_id,
		"nonce": String(data.get("nonce", "")),
		"challenge": String(data.get("challenge", "")),
		"secret": _registry_secret,
	}
	return _registry_auth_context


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	var raw_args := OS.get_cmdline_user_args()
	if raw_args.is_empty():
		raw_args = OS.get_cmdline_args()

	var i := 0
	while i < raw_args.size():
		var token := String(raw_args[i])
		if not token.begins_with("--"):
			i += 1
			continue

		var key := token.substr(2)
		var value: Variant = true
		if key.contains("="):
			var pair := key.split("=", false, 2)
			key = String(pair[0])
			value = String(pair[1])
		elif i + 1 < raw_args.size() and not String(raw_args[i + 1]).begins_with("--"):
			value = String(raw_args[i + 1])
			i += 1
		out[key] = value
		i += 1
	return out
