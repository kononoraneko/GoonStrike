## WeaponRegistry.gd — Autoload
## Реестр всех доступных оружий. Хранит словарь short_name → resource_path.
## Новое оружие = новый _register() в _ready().

extends Node

var _weapons: Dictionary = {}

## Фоллбэк цены/категории для оружий, у которых binary .res не содержит новых полей.
const _WEAPON_DEFAULTS: Dictionary = {
	"ar-15": {"price": 2700, "buy_category": "rifles"},
	"barret": {"price": 4750, "buy_category": "snipers"},
}


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


func get_all_weapon_data() -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for key in _weapons.keys():
		var data := load(String(_weapons[key])) as WeaponData
		if data:
			result.append(data)
	return result


func get_weapons_by_category() -> Dictionary:
	var cats: Dictionary = {}
	for key in _weapons.keys():
		var data := load(String(_weapons[key])) as WeaponData
		if data == null:
			continue
		var cat: String = data.buy_category if not data.buy_category.is_empty() else "other"
		if not cats.has(cat):
			cats[cat] = []
		cats[cat].append(data)
	return cats


func has_weapon(weapon_name: String) -> bool:
	return _weapons.has(weapon_name.strip_edges().to_lower())


func _register(res_path: String) -> void:
	var data := load(res_path) as WeaponData
	if data == null:
		push_warning("WeaponRegistry: не удалось загрузить %s" % res_path)
		return
	var key := data.weapon_name.strip_edges().to_lower()
	if _WEAPON_DEFAULTS.has(key):
		var defs: Dictionary = _WEAPON_DEFAULTS[key]
		if data.price == 0 and defs.has("price"):
			data.price = int(defs["price"])
		if data.buy_category.is_empty() and defs.has("buy_category"):
			data.buy_category = String(defs["buy_category"])
	_weapons[key] = res_path
