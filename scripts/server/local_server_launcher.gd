extends RefCounted
class_name LocalServerLauncher

## Starts a local dedicated server process for offline/LAN play.
## Backend is optional and is not used unless backend_url is provided.

const SERVER_SCENE := "res://scenes/server/server_bootstrap.tscn"


static func launch(port: int = 7000, map_id: String = "default", mode_id: String = "team_elim", backend_url: String = "") -> int:
	var executable := _get_server_executable()
	var args := _build_args(port, map_id, mode_id, backend_url)
	return OS.create_process(executable, args, false)


static func _get_server_executable() -> String:
	if OS.has_feature("editor"):
		return "godot4"
	return OS.get_executable_path()


static func _build_args(port: int, map_id: String, mode_id: String, backend_url: String) -> PackedStringArray:
	var args := PackedStringArray()
	args.append("--headless")
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append(SERVER_SCENE)
	args.append("--")
	args.append("--port")
	args.append(str(port))
	args.append("--map")
	args.append(map_id)
	args.append("--mode")
	args.append(mode_id)
	args.append("--auto-op-first")
	if not backend_url.strip_edges().is_empty():
		args.append("--backend-url")
		args.append(backend_url)
	return args
