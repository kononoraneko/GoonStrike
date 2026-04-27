extends Node

## Entry point for dedicated/headless server runs.
## Run with a server scene, for example:
## godot4 --headless --path . scenes/server/server_bootstrap.tscn -- --port 7000 --map default --mode team_elim

const DEFAULT_PORT := 7000
const DEFAULT_MAX_PLAYERS := 20

var _backend_client: Node


func _ready() -> void:
	call_deferred("_start_server")


func _start_server() -> void:
	var args := _parse_args()
	var port := int(args.get("port", DEFAULT_PORT))
	var max_players := int(args.get("max-players", DEFAULT_MAX_PLAYERS))
	var server_name := String(args.get("name", "dedicated"))
	var map_arg := String(args.get("map", ""))
	var mode_id := String(args.get("mode", GameModeCatalog.ID_TEAM_ELIM))
	var backend_url := String(args.get("backend-url", ""))
	var auto_start := bool(args.get("auto-start", false))
	var auto_op_first := bool(args.get("auto-op-first", false))

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
