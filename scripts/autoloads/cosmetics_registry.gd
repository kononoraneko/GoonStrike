extends Node

const DEFAULT_CHARACTER_ID := "lain"

const _WEAPON_SKIN_PATHS := [
	"res://resources/cosmetics/weapon_skins/ar15_default.tres",
	"res://resources/cosmetics/weapon_skins/ar15_gold.tres",
	"res://resources/cosmetics/weapon_skins/barret_default.tres",
	"res://resources/cosmetics/weapon_skins/barret_gold.tres",
]

const _CHARACTER_PATHS := [
	"res://resources/cosmetics/characters/lain.tres",
	"res://resources/cosmetics/characters/leama.tres",
]

var _weapon_skins: Dictionary = {}
var _characters: Dictionary = {}


func _ready() -> void:
	## Headless dedicated must not preload full client cosmetics (heavy scenes; missing VPS assets spam errors).
	if _is_headless_dedicated_cosmetics_stub():
		_load_minimal_headless_cosmetics()
		return
	_load_weapon_skins()
	_load_characters()


func _is_headless_dedicated_cosmetics_stub() -> bool:
	return DisplayServer.get_name() == "headless"


func _load_minimal_headless_cosmetics() -> void:
	## На dedicated в headless не тащим Character .tres/.res, чтобы не требовать .godot/imported текстуры.
	var cls := load("res://scripts/cosmetics/character_cosmetic_data.gd") as Script
	if cls != null:
		var fallback := cls.new() as Resource
		fallback.set("item_key", "character:%s" % DEFAULT_CHARACTER_ID)
		fallback.set("display_name", DEFAULT_CHARACTER_ID.capitalize())
		fallback.set("character_id", DEFAULT_CHARACTER_ID)
		_characters[String(fallback.get("item_key"))] = fallback
	else:
		push_warning("CosmeticsRegistry headless: failed to load CharacterCosmeticData script")

	for path in _WEAPON_SKIN_PATHS:
		var ws := load(path) as Resource
		if ws == null or ws.item_key.is_empty():
			push_warning("CosmeticsRegistry headless: skip weapon skin %s" % path)
			continue
		_weapon_skins[ws.item_key] = ws


func get_weapon_skin(item_key: String) -> Resource:
	return _weapon_skins.get(item_key, null) as Resource


func get_weapon_skin_for_weapon(item_key: String, weapon_short_name: String) -> Resource:
	var skin: Resource = get_weapon_skin(item_key)
	if skin == null:
		return null
	return skin if skin.weapon_short_name == weapon_short_name.strip_edges().to_lower() else null


func get_character_cosmetic(item_key: String) -> Resource:
	return _characters.get(item_key, null) as Resource


func get_character_scene(character_id: String) -> PackedScene:
	var normalized := character_id.strip_edges().to_lower()
	for data in _characters.values():
		var character := data as Resource
		if character != null and character.character_id == normalized:
			return character.character_scene
	return null


func get_character_id_for_item(item_key: String) -> String:
	var data: Resource = get_character_cosmetic(item_key)
	return data.character_id if data != null else DEFAULT_CHARACTER_ID


func has_character_id(character_id: String) -> bool:
	return get_character_scene(character_id) != null


func get_all_character_cosmetics() -> Array[Resource]:
	var result: Array[Resource] = []
	for data in _characters.values():
		if data is Resource:
			result.append(data as Resource)
	return result


func get_weapon_skins_for_weapon(weapon_short_name: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var normalized := weapon_short_name.strip_edges().to_lower()
	for data in _weapon_skins.values():
		var skin := data as Resource
		if skin != null and skin.weapon_short_name == normalized:
			result.append(skin)
	return result


func _load_weapon_skins() -> void:
	for path in _WEAPON_SKIN_PATHS:
		var data := load(path) as Resource
		if data == null or data.item_key.is_empty():
			push_warning("CosmeticsRegistry: failed to load weapon skin %s" % path)
			continue
		_weapon_skins[data.item_key] = data


func _load_characters() -> void:
	for path in _CHARACTER_PATHS:
		var data := load(path) as Resource
		if data == null or data.item_key.is_empty():
			push_warning("CosmeticsRegistry: failed to load character cosmetic %s" % path)
			continue
		_characters[data.item_key] = data
