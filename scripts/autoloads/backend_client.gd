extends Node

## HTTP bridge from the authoritative Godot server to the persistent backend API.
## Clients should not use this for gameplay authority or direct DB access.

const DEFAULT_TIMEOUT := 5.0

var base_url: String = ""
var request_timeout_sec: float = DEFAULT_TIMEOUT


func configure(url: String, timeout_sec: float = DEFAULT_TIMEOUT) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	request_timeout_sec = timeout_sec


func is_configured() -> bool:
	return not base_url.is_empty()


func ping_health() -> void:
	if not is_configured():
		return
	_request("GET", "/health")


func upsert_player(peer_id: int, info: Dictionary) -> void:
	if not is_configured():
		return
	var display_name := str(info.get("name", "Player"))
	var payload := {
		"external_id": _external_id_for_peer(peer_id),
		"display_name": display_name,
	}
	_request("POST", "/players/upsert", payload)


func submit_match_result(match_id: String, mode_id: String, map_id: String, stats: Dictionary, winner_ids: Array[int] = []) -> void:
	if not is_configured():
		return
	var winners := {}
	for id in winner_ids:
		winners[int(id)] = true

	var players: Array = []
	for peer_id in stats.keys():
		var id := int(peer_id)
		if id <= 0 or GameManager.is_host_spectator(id):
			continue
		var entry: Dictionary = stats[peer_id] if stats[peer_id] is Dictionary else {}
		players.append({
			"external_id": _external_id_for_peer(id),
			"display_name": Lobby.get_player_display_name(id),
			"kills": int(entry.get("k", 0)),
			"deaths": int(entry.get("d", 0)),
			"assists": int(entry.get("a", 0)),
			"won": winners.has(id),
		})

	if players.is_empty():
		return

	var payload := {
		"match_id": match_id,
		"mode_id": mode_id,
		"map_id": map_id,
		"players": players,
	}
	_request("POST", "/matches", payload)


func _external_id_for_peer(peer_id: int) -> String:
	# Placeholder identity until real auth exists.
	return "peer:%d" % peer_id


func _request(method: String, path: String, payload: Variant = null) -> void:
	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)
	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if response_code < 200 or response_code >= 300:
			push_warning("Backend request %s %s failed: HTTP %d %s" % [
				method,
				path,
				response_code,
				body.get_string_from_utf8(),
			])
		http.queue_free()
	, CONNECT_ONE_SHOT)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := ""
	if payload != null:
		body = JSON.stringify(payload)

	var err := http.request(base_url + path, headers, _http_method(method), body)
	if err != OK:
		push_warning("Backend request %s %s could not start: %d" % [method, path, err])
		http.queue_free()


func _http_method(method: String) -> int:
	match method.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET
