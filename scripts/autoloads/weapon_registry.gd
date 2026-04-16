## WeaponRegistry.gd — Autoload
## Реестр всех доступных оружий. Хранит словарь short_name → resource_path.
## Новое оружие = новый _register() в _ready().

extends Node

var _weapons: Dictionary = {}


func _ready() -> void:
	_register("res://resources/ar-15_data.res")
	_register("res://resources/barret.res")


func get_weapon_path(weapon_name: String) -> String:
	var key := weapon_name.strip_edges().to_lower()
	return String(_weapons.get(key, ""))


func get_all_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for k in _weapons.keys():
		names.append(String(k))
	names.sort()
	return names


func has_weapon(weapon_name: String) -> bool:
	return _weapons.has(weapon_name.strip_edges().to_lower())


func _register(res_path: String) -> void:
	var data := load(res_path) as WeaponData
	if data == null:
		push_warning("WeaponRegistry: не удалось загрузить %s" % res_path)
		return
	var key := data.weapon_name.strip_edges().to_lower()
	_weapons[key] = res_path
