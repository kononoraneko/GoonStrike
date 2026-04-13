class_name GameModeCatalog extends RefCounted

const ID_DM := "dm"
const ID_TEAM_ELIM := "team_elim"

const SCENES: Dictionary = {
	ID_DM: preload("res://scenes/game_modes/deathmatch_mode_node.tscn"),
	ID_TEAM_ELIM: preload("res://scenes/game_modes/team_elimination_mode_node.tscn"),
}

const DISPLAY := {
	ID_DM: "Deathmatch",
	ID_TEAM_ELIM: "Командный (elimination)",
}


static func get_mode_scene(mode_id: String) -> PackedScene:
	var sc: Variant = SCENES.get(mode_id, null)
	if sc is PackedScene:
		return sc
	return SCENES[ID_DM] as PackedScene


static func all_mode_ids() -> PackedStringArray:
	return PackedStringArray([ID_DM, ID_TEAM_ELIM])


static func display_name(mode_id: String) -> String:
	return str(DISPLAY.get(mode_id, mode_id))


static func is_team_mode(mode_id: String) -> bool:
	return mode_id == ID_TEAM_ELIM
