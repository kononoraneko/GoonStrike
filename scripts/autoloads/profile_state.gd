extends Node

signal profile_changed
signal backend_availability_changed(available: bool)

const DEFAULT_CHARACTER_ITEM := "character:lain"
const DEFAULT_EQUIPPED := {
	"character": DEFAULT_CHARACTER_ITEM,
	"weapon:ar-15": "weapon_skin:ar-15:default",
	"weapon:barret": "weapon_skin:barret:default",
}

var external_id: String = ""
var backend_available: bool = false
var wallet: Dictionary = {}
var inventory: Dictionary = {}
var equipped: Dictionary = DEFAULT_EQUIPPED.duplicate()
var catalog_items: Dictionary = {}
var catalog_cases: Array[Dictionary] = []


func _ready() -> void:
	external_id = _resolve_external_id()
	_apply_offline_defaults()


func load_profile(display_name: String = "Player") -> void:
	external_id = _resolve_external_id()
	_apply_offline_defaults()
	if not BackendClient.is_configured():
		_set_backend_available(false)
		profile_changed.emit()
		return

	var catalog_result := await BackendClient.fetch_catalog()
	if catalog_result.get("ok", false):
		_apply_catalog(catalog_result.get("data", {}))

	var profile_result: Dictionary
	if AuthState.is_authenticated():
		profile_result = await BackendClient.fetch_profile_me()
	else:
		profile_result = await BackendClient.fetch_profile(external_id)
	if not profile_result.get("ok", false):
		_set_backend_available(false)
		profile_changed.emit()
		return

	_set_backend_available(true)
	_apply_profile(profile_result.get("data", {}))
	profile_changed.emit()


func get_wallet_amount(currency_key: String) -> int:
	return int(wallet.get(currency_key, 0))


func get_inventory_items() -> Array[String]:
	var keys: Array[String] = []
	for item_key in inventory.keys():
		keys.append(String(item_key))
	keys.sort()
	return keys


func owns_item(item_key: String) -> bool:
	return inventory.has(item_key)


func get_equipped_item(slot_key: String) -> String:
	return String(equipped.get(slot_key, DEFAULT_EQUIPPED.get(slot_key, "")))


func get_equipped_character_id() -> String:
	var item_key := get_equipped_item("character")
	if item_key.begins_with("character:"):
		return item_key.trim_prefix("character:")
	return "lain"


func get_equipped_weapon_skin(weapon_short_name: String) -> String:
	var slot_key := "weapon:%s" % weapon_short_name.strip_edges().to_lower()
	return get_equipped_item(slot_key)


func equip_cosmetic(slot_key: String, item_key: String) -> bool:
	if not owns_item(item_key):
		return false
	if BackendClient.is_configured() and backend_available:
		var result := await BackendClient.equip_cosmetic(external_id, slot_key, item_key)
		if not result.get("ok", false):
			return false
	equipped[slot_key] = item_key
	_save_local_cosmetics()
	profile_changed.emit()
	return true


func set_local_character_id(character_id: String) -> void:
	var item_key := "character:%s" % character_id.strip_edges().to_lower()
	if not owns_item(item_key):
		inventory[item_key] = {"item_key": item_key, "quantity": 1, "source": "local"}
	equipped["character"] = item_key
	Settings.set_selected_character_id(character_id)
	_save_local_cosmetics()
	profile_changed.emit()


func open_case(case_key: String) -> Dictionary:
	if not BackendClient.is_configured() or not backend_available or not AuthState.is_authenticated():
		return {"ok": false, "offline": true, "error": "cases require backend"}
	var result := await BackendClient.open_case(external_id, case_key)
	if result.get("ok", false):
		var data: Dictionary = result.get("data", {})
		_apply_wallet_array(data.get("wallet", []))
		var item: Dictionary = data.get("inventory_item", {})
		if item.has("item_key"):
			inventory[String(item["item_key"])] = item
		profile_changed.emit()
	return result


func grant_dev_currency(currency_key: String, amount: int) -> bool:
	if not BackendClient.is_configured() or not backend_available or not AuthState.is_authenticated():
		return false
	var result := await BackendClient.grant_dev_currency(external_id, currency_key, amount)
	if not result.get("ok", false):
		return false
	var balance: Dictionary = result.get("data", {}).get("balance", {})
	if balance.has("currency_key"):
		wallet[String(balance["currency_key"])] = int(balance.get("amount", 0))
		profile_changed.emit()
	return true


func get_available_cases() -> Array[Dictionary]:
	return catalog_cases.duplicate(true)


func _resolve_external_id() -> String:
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		return "guest:local"
	return "guest:%s" % device_id


func _set_backend_available(available: bool) -> void:
	if backend_available == available:
		return
	backend_available = available
	backend_availability_changed.emit(backend_available)


func _apply_offline_defaults() -> void:
	wallet = {}
	inventory = {}
	equipped = DEFAULT_EQUIPPED.duplicate()
	for item_key in DEFAULT_EQUIPPED.values():
		inventory[String(item_key)] = {"item_key": item_key, "quantity": 1, "source": "default"}
	_load_local_cosmetics()


func _apply_catalog(data: Dictionary) -> void:
	catalog_items.clear()
	catalog_cases.clear()
	for item in data.get("items", []):
		if item is Dictionary and item.has("item_key"):
			catalog_items[String(item["item_key"])] = item
	for case_data in data.get("cases", []):
		if case_data is Dictionary:
			catalog_cases.append(case_data)


func _apply_profile(data: Dictionary) -> void:
	wallet.clear()
	inventory.clear()
	equipped.clear()
	_apply_wallet_array(data.get("wallet", []))
	for item in data.get("inventory", []):
		if item is Dictionary and item.has("item_key"):
			inventory[String(item["item_key"])] = item
	for entry in data.get("equipped", []):
		if entry is Dictionary and entry.has("slot_key") and entry.has("item_key"):
			equipped[String(entry["slot_key"])] = String(entry["item_key"])
	for slot_key in DEFAULT_EQUIPPED.keys():
		if not equipped.has(slot_key):
			equipped[slot_key] = DEFAULT_EQUIPPED[slot_key]


func _apply_wallet_array(entries: Array) -> void:
	for entry in entries:
		if entry is Dictionary and entry.has("currency_key"):
			wallet[String(entry["currency_key"])] = int(entry.get("amount", 0))


func _load_local_cosmetics() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.SETTINGS_PATH) != OK:
		return
	if cfg.has_section_key("cosmetics", "character_item"):
		equipped["character"] = String(cfg.get_value("cosmetics", "character_item", DEFAULT_CHARACTER_ITEM))
	for slot_key in ["weapon:ar-15", "weapon:barret"]:
		var cfg_key: String = String(slot_key).replace(":", "_")
		if cfg.has_section_key("cosmetics", cfg_key):
			equipped[slot_key] = String(cfg.get_value("cosmetics", cfg_key, DEFAULT_EQUIPPED[slot_key]))
	for item_key in equipped.values():
		inventory[String(item_key)] = {"item_key": item_key, "quantity": 1, "source": "local"}


func _save_local_cosmetics() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Settings.SETTINGS_PATH)
	cfg.set_value("cosmetics", "character_item", get_equipped_item("character"))
	for slot_key in ["weapon:ar-15", "weapon:barret"]:
		cfg.set_value("cosmetics", slot_key.replace(":", "_"), get_equipped_item(slot_key))
	cfg.save(Settings.SETTINGS_PATH)
