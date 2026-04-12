extends Node

@export var potato :bool = true:
	set(val):
		potato_changed.emit(val)

signal potato_changed(val)

func _ready() -> void:
	connect("potato_changed", _on_potato_changed)

func _on_potato_changed(val) -> void:
	if val:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_size(Vector2i(640,320))
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
