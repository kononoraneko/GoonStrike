extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"

@onready var potato_check: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/TabContainer/Графика/PotatoCheck
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CloseButton

static func open(parent: Node) -> CanvasLayer:
	var scene := preload("res://scenes/settings/settings_screen.tscn")
	var inst := scene.instantiate() as CanvasLayer
	parent.add_child(inst)
	return inst


func _ready() -> void:
	_load()
	potato_check.button_pressed = Settings.potato

	potato_check.toggled.connect(_on_potato_toggled)
	close_button.pressed.connect(_on_close_pressed)


func _on_potato_toggled(val: bool) -> void:
	Settings.potato = val
	_save()



func _on_close_pressed() -> void:
	queue_free()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "potato", Settings.potato)
	cfg.set_value("video", "is_hair_animation", Settings.is_hair_animation)
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if cfg.has_section_key("video", "potato"):
		Settings.potato = bool(cfg.get_value("video", "potato"))
