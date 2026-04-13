class_name CharacterData extends Resource

## Данные персонажа для выбора в лобби / спавна. Контент — через .tres в resources/characters/.

@export var id: String = ""
@export var display_name: String = ""
@export var character_scene: PackedScene
@export var icon: Texture2D
