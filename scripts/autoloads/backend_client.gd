extends Node

## HTTP bridge from the authoritative Godot server to the persistent backend API.
## Clients should not use this for gameplay authority or direct DB access.

signal auth_response_failed(status: int, detail: String)

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


func fetch_profile(external_id: String) -> Dictionary:
	return await _request_json("GET", "/profile/%s" % external_id.uri_encode())


func fetch_profile_me() -> Dictionary:
	return await _request_json("GET", "/profile/me")


func fetch_catalog() -> Dictionary:
	return await _request_json("GET", "/catalog")


func fetch_servers() -> Dictionary:
	return await _request_json("GET", "/servers", null, false)


func fetch_server_challenge(server_id: String, key_id: String) -> Dictionary:
	if not is_configured() or server_id.is_empty() or key_id.is_empty():
		return {"ok": false, "offline": true, "status": 0, "data": {}}
	return await _request_json("POST", "/servers/challenge", {
		"server_id": server_id,
		"key_id": key_id,
	}, false)


func registry_enroll(enrollment_token: String, server_id: String) -> Dictionary:
	if not is_configured() or enrollment_token.is_empty() or server_id.is_empty():
		return {"ok": false, "offline": false, "status": 400, "data": {}}
	return await _request_json("POST", "/servers/registry/enroll", {
		"enrollment_token": enrollment_token,
		"server_id": server_id,
	}, false)


func register_server(payload: Dictionary, auth_context: Dictionary = {}) -> void:
	if not is_configured():
		return
	_request("POST", "/servers/register", payload, _registry_headers("POST", "/servers/register", payload, auth_context))


func heartbeat_server(server_id: String, payload: Dictionary, auth_context: Dictionary = {}) -> void:
	if not is_configured() or server_id.is_empty():
		return
	var path := "/servers/%s/heartbeat" % server_id.uri_encode()
	_request("POST", path, payload, _registry_headers("POST", path, payload, auth_context))


func mark_server_offline(server_id: String, auth_context: Dictionary = {}) -> void:
	if not is_configured() or server_id.is_empty():
		return
	var path := "/servers/%s/offline" % server_id.uri_encode()
	_request("POST", path, null, _registry_headers("POST", path, null, auth_context))


func fetch_inventory(external_id: String) -> Dictionary:
	var result := await _request_json("GET", "/inventory/%s" % external_id.uri_encode())
	if result.get("ok", false) and result.get("data") is Array:
		result["data"] = {"items": result["data"]}
	return result


func fetch_inventory_me() -> Dictionary:
	var result := await _request_json("GET", "/inventory/me")
	if result.get("ok", false) and result.get("data") is Array:
		result["data"] = {"items": result["data"]}
	return result


func auth_register(email: String, password: String, display_name: String, device_label: String = "") -> Dictionary:
	return await _request_json("POST", "/auth/register", {
		"email": email,
		"password": password,
		"display_name": display_name,
		"device_label": device_label,
	}, false)


func auth_login(email: String, password: String, device_label: String = "") -> Dictionary:
	return await _request_json("POST", "/auth/login", {
		"email": email,
		"password": password,
		"device_label": device_label,
	}, false)


func auth_refresh(refresh_token: String) -> Dictionary:
	return await _request_json("POST", "/auth/refresh", {"refresh_token": refresh_token}, false)


func auth_logout(refresh_token: String) -> Dictionary:
	return await _request_json("POST", "/auth/logout", {"refresh_token": refresh_token}, false)


func auth_me() -> Dictionary:
	return await _request_json("GET", "/auth/me")


func equip_cosmetic(external_id: String, slot_key: String, item_key: String) -> Dictionary:
	return await _request_json("POST", "/inventory/equip", {
		"external_id": external_id,
		"slot_key": slot_key,
		"item_key": item_key,
	})


func open_case(external_id: String, case_key: String) -> Dictionary:
	return await _request_json("POST", "/cases/open", {
		"external_id": external_id,
		"case_key": case_key,
	})


func grant_dev_currency(external_id: String, currency_key: String, amount: int) -> Dictionary:
	return await _request_json("POST", "/wallet/grant-dev", {
		"external_id": external_id,
		"currency_key": currency_key,
		"amount": amount,
	})


func upsert_player(peer_id: int, info: Dictionary) -> void:
	if not is_configured():
		return
	var display_name := str(info.get("name", "Player"))
	var payload := {
		"external_id": get_external_id_for_player(peer_id, info),
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
			"external_id": get_external_id_for_player(id, Lobby.players.get(id, {}) as Dictionary),
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


func get_external_id_for_peer(peer_id: int) -> String:
	# Placeholder identity until real auth exists.
	return "peer:%d" % peer_id


func get_external_id_for_player(peer_id: int, info: Dictionary) -> String:
	var provided := String(info.get("external_id", "")).strip_edges()
	return provided if not provided.is_empty() else get_external_id_for_peer(peer_id)


func _request(method: String, path: String, payload: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> void:
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

	var headers := _make_headers(false)
	for header in extra_headers:
		headers.append(header)
	var body := _request_body(payload)

	var err := http.request(base_url + path, headers, _http_method(method), body)
	if err != OK:
		push_warning("Backend request %s %s could not start: %d" % [method, path, err])
		http.queue_free()


func _request_json(method: String, path: String, payload: Variant = null, include_auth: bool = true) -> Dictionary:
	if not is_configured():
		return {"ok": false, "offline": true, "status": 0, "data": {}}

	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)

	var headers := _make_headers(include_auth)
	var body := _request_body(payload)

	var err := http.request(base_url + path, headers, _http_method(method), body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "offline": false, "status": 0, "error": "request_start_failed:%d" % err}

	var completed: Array = await http.request_completed
	http.queue_free()
	var result := int(completed[0])
	var response_code := int(completed[1])
	var response_body := completed[3] as PackedByteArray
	var text := response_body.get_string_from_utf8()
	var data: Variant = {}
	if not text.is_empty():
		var parsed: Variant = JSON.parse_string(text)
		if parsed != null:
			data = parsed
	var response := {
		"ok": result == OK and response_code >= 200 and response_code < 300,
		"offline": false,
		"status": response_code,
		"data": data,
		"raw": text,
	}
	if response_code == 401 or response_code == 409:
		auth_response_failed.emit(response_code, _response_detail(response))
	return response


func _make_headers(include_auth: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if include_auth:
		var auth_state := get_node_or_null("/root/AuthState")
		if auth_state != null and auth_state.has_method("get_access_token"):
			var token := String(auth_state.call("get_access_token"))
			if not token.is_empty():
				headers.append("Authorization: Bearer %s" % token)
	return headers


func _registry_headers(method: String, path: String, payload: Variant, auth_context: Dictionary) -> PackedStringArray:
	var server_id := String(auth_context.get("server_id", "")).strip_edges()
	var key_id := String(auth_context.get("key_id", "")).strip_edges()
	var nonce := String(auth_context.get("nonce", "")).strip_edges()
	var challenge := String(auth_context.get("challenge", "")).strip_edges()
	var secret := String(auth_context.get("secret", "")).strip_edges()
	if server_id.is_empty() or key_id.is_empty() or nonce.is_empty() or challenge.is_empty() or secret.is_empty():
		return PackedStringArray()

	var body := _request_body(payload)
	var payload_hash := _sha256_hex(body)
	var canonical := "%s\n%s\n%s\n%s\n%s\n%s\n%s" % [
		method.to_upper(),
		path,
		server_id,
		key_id,
		nonce,
		challenge,
		payload_hash,
	]
	var secret_hash := _sha256_hex(secret)
	var signature := _sha256_hex("%s\n%s" % [canonical, secret_hash])
	return PackedStringArray([
		"X-GS-Server-Id: %s" % server_id,
		"X-GS-Key-Id: %s" % key_id,
		"X-GS-Nonce: %s" % nonce,
		"X-GS-Challenge: %s" % challenge,
		"X-GS-Signature: %s" % signature,
	])


func _request_body(payload: Variant) -> String:
	return JSON.stringify(payload) if payload != null else ""


func _sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _response_detail(response: Dictionary) -> String:
	var data: Variant = response.get("data", {})
	if data is Dictionary:
		return str((data as Dictionary).get("detail", ""))
	return str(response.get("raw", ""))


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
