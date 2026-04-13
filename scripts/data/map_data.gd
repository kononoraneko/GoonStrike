class_name MapData extends Resource

## Карта матча: оболочка мира (обычно game_world.tscn), инстанцирующая уровень.

@export var id: String = ""
@export var display_name: String = ""
@export var game_world_scene: PackedScene
@export var supported_mode_ids: PackedStringArray = []
