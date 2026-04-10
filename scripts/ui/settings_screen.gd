class_name SettingsScreen
extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"

@onready var potato_check: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/TabContainer/Графика/PotatoCheck
@onready var hair_check: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/TabContainer/Графика/HairCheck
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CloseButton

static func open(parent: Node) -> SettingsScreen:
	var scene := preload("res://scenes/settings/settings_screen.tscn")
	var inst := scene.instantiate() as SettingsScreen
	parent.add_child(inst)
	return inst


func _ready() -> void:
	_load()
	potato_check.button_pressed = Settings.potato
	hair_check.button_pressed = Settings.is_hair_animation

	potato_check.toggled.connect(_on_potato_toggled)
	hair_check.toggled.connect(_on_hair_toggled)
	close_button.pressed.connect(_on_close_pressed)


func _on_potato_toggled(val: bool) -> void:
	Settings.potato = val
	_save()


func _on_hair_toggled(val: bool) -> void:
	Settings.is_hair_animation = val
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
	if cfg.has_section_key("video", "is_hair_animation"):
		Settings.is_hair_animation = bool(cfg.get_value("video", "is_hair_animation"))
