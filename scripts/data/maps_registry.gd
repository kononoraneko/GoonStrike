class_name MapsRegistry extends RefCounted

## Список карт (.tres MapData) для выбора в лобби.
const MAP_PATHS: Array[String] = ["res://resources/maps/default.tres"]


static func load_all_maps() -> Array[MapData]:
	var out: Array[MapData] = []
	for p in MAP_PATHS:
		var m := load(p) as MapData
		if m != null and m.game_world_scene != null:
			out.append(m)
	return out
