extends Node

@export var is_hair_animation: bool = false
@export var potato :bool = true:
	set(val):
		potato_changed.emit(val)

signal potato_changed(val)
