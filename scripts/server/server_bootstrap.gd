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
	var port: int
	if args.has("port"):
		port = clampi(int(args.get("port", DEFAULT_PORT)), 1, 65535)
	else:
		var penv := String(OS.get_environment("GOONSTRIKE_DEDICATED_PORT")).strip_edges()
		if penv.is_empty():
			penv = String(OS.get_environment("PORT")).strip_edges()
		if not penv.is_empty() and penv.is_valid_int():
			port = clampi(int(penv), 1, 65535)
		else:
			port = DEFAULT_PORT
	var max_players := int(args.get("max-players", DEFAULT_MAX_PLAYERS))
	var server_name := String(args.get("name", "dedicated"))
	var map_arg := String(args.get("map", "")).strip_edges()
	if map_arg.is_empty():
		map_arg = String(OS.get_environment("GOONSTRIKE_MAP_ID")).strip_edges()
	var mode_id := String(args.get("mode", "")).strip_edges()
	if mode_id.is_empty():
		mode_id = String(OS.get_environment("GOONSTRIKE_MODE_ID")).strip_edges()
	if mode_id.is_empty():
		mode_id = GameModeCatalog.ID_TEAM_ELIM
	var backend_url := String(args.get("backend-url", "")).strip_edges()
	if backend_url.is_empty():
		backend_url = String(OS.get_environment("GOONSTRIKE_BACKEND_URL")).strip_edges()
	var auto_start := _bool_arg(args.get("auto-start", false))
	var auto_op_first := _bool_arg(args.get("auto-op-first", false))
	var heartbeat_sec := float(args.get("heartbeat-sec", 10.0))
	_display_name = String(args.get("display-name", server_name))
	if args.has("public-host"):
		_public_host = String(args.get("public-host", "127.0.0.1"))
	else:
		var ph := String(OS.get_environment("GOONSTRIKE_PUBLIC_HOST")).strip_edges()
		_public_host = ph if not ph.is_empty() else "127.0.0.1"
	var sid_arg := String(args.get("server-id", "")).strip_edges()
	if sid_arg.is_empty():
		sid_arg = String(OS.get_environment("GOONSTRIKE_SERVER_ID")).strip_edges()
	_server_id = sid_arg if not sid_arg.is_empty() else _make_default_server_id(_display_name, port)
	_is_trusted = _bool_arg(args.get("trusted", true))
	_registry_key_id = _resolve_arg_or_env(args, "registry-key-id", "GOONSTRIKE_REGISTRY_KEY_ID")
	_registry_secret = _resolve_arg_or_env(args, "registry-secret", "GOONSTRIKE_REGISTRY_SECRET")

	_setup_backend_client(backend_url)
	print(
		"[GoonStrike dedicated] port=%d server_id=%s public_host=%s backend_url=%s map=%s mode=%s"
		% [port, _server_id, _public_host, backend_url if not backend_url.is_empty() else "<none>", map_arg, mode_id]
	)
	await _resolve_registry_credentials_after_backend(args)

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
	if _backend_client == null:
		return
	var auth_context := await _auth_context_for_registry(true)
	var payload_identity := _build_registry_payload(true)

	if _backend_client.has_method("registry_signed_request_await"):
		var reg_result: Variant = await _backend_client.registry_signed_request_await(
			"POST",
			"/servers/register",
			payload_identity,
			auth_context,
		)
		if reg_result is Dictionary and not reg_result.get("ok", false):
			var msg := (
				"Registry register failed HTTP %s: %s"
				% [str(reg_result.get("status", "")), str(reg_result.get("raw", reg_result))]
			)
			push_error(msg)
			print("[GoonStrike dedicated] %s" % msg)
			return
		print("[GoonStrike dedicated] Registry register OK (HTTP %s)" % str(reg_result.get("status", "")))
	elif _backend_client.has_method("register_server"):
		_backend_client.call("register_server", payload_identity, auth_context)
	else:
		return

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


func _resolve_credentials_path(args: Dictionary) -> String:
	var path_arg := _resolve_arg_or_env(args, "registry-credentials-path", "GOONSTRIKE_REGISTRY_CREDENTIALS_PATH")
	return path_arg if not path_arg.is_empty() else "user://goonstrike_dedicated_registry.cfg"


func _resolve_registry_credentials_after_backend(args: Dictionary) -> void:
	if _backend_client == null:
		return
	if _requires_registry_auth():
		return

	var cred_path := _resolve_credentials_path(args)
	var enroll_token := _resolve_arg_or_env(args, "registry-enroll-token", "GOONSTRIKE_REGISTRY_ENROLL_TOKEN")
	var enroll_force := _bool_arg(args.get("registry-enroll-force", false))

	if not enroll_token.is_empty():
		if not enroll_force and _try_load_registry_credentials_file(cred_path):
			print("Loaded registry credentials from %s (skipped enrollment)." % cred_path)
			return
		if not _backend_client.has_method("registry_enroll"):
			push_error("BackendClient.registry_enroll missing; cannot use registry enrollment.")
			return
		var enroll_result: Dictionary = await _backend_client.registry_enroll(enroll_token, _server_id)
		if not enroll_result.get("ok", false):
			push_error(
				"Registry enrollment failed (HTTP %s): %s"
				% [str(enroll_result.get("status", "")), str(enroll_result.get("raw", enroll_result))]
			)
			return
		var enroll_data: Dictionary = enroll_result.get("data", {}) as Dictionary
		var kid := String(enroll_data.get("key_id", "")).strip_edges()
		var sec := String(enroll_data.get("secret", "")).strip_edges()
		if kid.is_empty() or sec.is_empty():
			push_error("Registry enrollment returned empty key_id/secret.")
			return
		_registry_key_id = kid
		_registry_secret = sec
		_save_registry_credentials_file(cred_path)
		print("Registry enrolled; credentials saved to %s" % cred_path)
		return

	if _try_load_registry_credentials_file(cred_path):
		print("Loaded registry credentials from %s" % cred_path)


func _try_load_registry_credentials_file(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	if not cfg.has_section("registry"):
		return false
	var kid := String(cfg.get_value("registry", "key_id", "")).strip_edges()
	var sec := String(cfg.get_value("registry", "secret", "")).strip_edges()
	if kid.is_empty() or sec.is_empty():
		return false
	var sid := String(cfg.get_value("registry", "server_id", "")).strip_edges()
	if not sid.is_empty() and sid != _server_id:
		return false
	_registry_key_id = kid
	_registry_secret = sec
	return true


func _save_registry_credentials_file(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("registry", "server_id", _server_id)
	cfg.set_value("registry", "key_id", _registry_key_id)
	cfg.set_value("registry", "secret", _registry_secret)
	var err := cfg.save(path)
	if err != OK:
		push_warning("Could not save registry credentials to '%s' (error %d)." % [path, err])


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
