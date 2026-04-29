extends Node

signal auth_changed
signal session_conflict
signal auth_error(message: String)

const DEFAULT_BACKEND_URL := "http://193.164.155.194:8000"

const ENV_BACKEND_URL := "GOONSTRIKE_CLIENT_BACKEND_URL"
const CFG_SECTION := "auth"

var account: Dictionary = {}
var access_token: String = ""
var refresh_token: String = ""
var status: String = "offline"


func _ready() -> void:
	if not BackendClient.is_configured():
		BackendClient.configure(_resolve_client_backend_url())
	BackendClient.auth_response_failed.connect(_on_backend_auth_failed)
	_load_refresh_token()
	if not refresh_token.is_empty():
		call_deferred("refresh")


func is_authenticated() -> bool:
	return not access_token.is_empty() and not account.is_empty()


func get_access_token() -> String:
	return access_token


func register(email: String, password: String, display_name: String) -> bool:
	var result := await BackendClient.auth_register(email, password, display_name, _device_label())
	return _handle_auth_result(result)


func login(email: String, password: String) -> bool:
	var result := await BackendClient.auth_login(email, password, _device_label())
	return _handle_auth_result(result)


func refresh() -> bool:
	if refresh_token.is_empty():
		_set_offline()
		return false
	var result := await BackendClient.auth_refresh(refresh_token)
	return _handle_auth_result(result)


func logout() -> void:
	if not refresh_token.is_empty() and BackendClient.is_configured():
		await BackendClient.auth_logout(refresh_token)
	_clear_tokens()
	status = "offline"
	auth_changed.emit()


func _handle_auth_result(result: Dictionary) -> bool:
	if result.get("ok", false):
		_apply_tokens(result.get("data", {}))
		return true
	var status_code := int(result.get("status", 0))
	var data: Variant = result.get("data", {})
	var raw_detail := ""
	if data is Dictionary:
		raw_detail = str((data as Dictionary).get("detail", ""))
	if status_code == 409 and raw_detail == "session_conflict":
		_clear_tokens()
		status = "session_conflict"
		session_conflict.emit()
		auth_changed.emit()
		return false
	var detail := _result_detail(result)
	status = "offline"
	auth_error.emit(detail if not detail.is_empty() else "auth failed")
	auth_changed.emit()
	return false


func _apply_tokens(data: Dictionary) -> void:
	account = data.get("account", {}) as Dictionary
	access_token = String(data.get("access_token", ""))
	refresh_token = String(data.get("refresh_token", ""))
	status = "authenticated" if is_authenticated() else "offline"
	_save_refresh_token()
	auth_changed.emit()
	if is_authenticated():
		ProfileState.load_profile()


func _on_backend_auth_failed(status_code: int, detail: String) -> void:
	if status_code == 409 and detail == "session_conflict":
		_clear_tokens()
		status = "session_conflict"
		session_conflict.emit()
		auth_changed.emit()
	elif status_code == 401:
		_clear_tokens()
		status = "offline"
		auth_changed.emit()


func _set_offline() -> void:
	status = "offline"
	account.clear()
	access_token = ""
	auth_changed.emit()


func _clear_tokens() -> void:
	account.clear()
	access_token = ""
	refresh_token = ""
	_save_refresh_token()


func _load_refresh_token() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.SETTINGS_PATH) != OK:
		return
	refresh_token = String(cfg.get_value(CFG_SECTION, "refresh_token", ""))


func _save_refresh_token() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Settings.SETTINGS_PATH)
	if refresh_token.is_empty():
		cfg.erase_section_key(CFG_SECTION, "refresh_token")
	else:
		cfg.set_value(CFG_SECTION, "refresh_token", refresh_token)
	cfg.save(Settings.SETTINGS_PATH)


func _resolve_client_backend_url() -> String:
	var env := String(OS.get_environment(ENV_BACKEND_URL)).strip_edges().trim_suffix("/")
	return env if not env.is_empty() else DEFAULT_BACKEND_URL


func _result_detail(result: Dictionary) -> String:
	var status := int(result.get("status", 0))
	var data: Variant = result.get("data", {})
	var detail := ""
	if data is Dictionary:
		var d: Variant = (data as Dictionary).get("detail", "")
		if d is Array:
			detail = JSON.stringify(d)
		else:
			detail = str(d)
	if detail.is_empty():
		detail = str(result.get("raw", ""))
	var base := BackendClient.base_url if BackendClient.is_configured() else ""
	
	if status > 0 and not detail.is_empty():
		return "%s (HTTP %d)" % [detail, status]
	return detail


func _device_label() -> String:
	return "%s:%s" % [OS.get_name(), OS.get_unique_id()]
